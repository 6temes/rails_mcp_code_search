module RailsMcpCodeSearch
  class BackgroundWorker
    REINDEX_COOLDOWN = 60

    attr_reader :state, :progress, :errors

    def initialize(indexer:, logger: nil)
      @indexer = indexer
      @logger = logger
      @queue = Queue.new
      @mutex = Mutex.new
      @state = :idle
      @progress = 0.0
      @errors = []
      @stop_requested = false
      @last_full_reindex_at = nil
      @hit_count_buffer = []
      @search_count = 0
      @reindex_count = 0
    end

    def start
      @thread = Thread.new { run }
      enqueue(:full_index)
      self
    end

    def stop
      @stop_requested = true
      @queue.push(:shutdown)
      @thread&.join(5)
    end

    def enqueue(work_type, payload: nil)
      @queue.push({ type: work_type, payload: })
    end

    def enqueue_hit_counts(chunk_ids)
      @mutex.synchronize { @hit_count_buffer.concat(chunk_ids) }
    end

    def increment_search_count
      @mutex.synchronize { @search_count += 1 }
    end

    def increment_reindex_count
      @mutex.synchronize { @reindex_count += 1 }
    end

    def wait_for_reindex(timeout: 0.2)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        return true if @mutex.synchronize { @state } == :idle
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return false if remaining <= 0
        sleep([ remaining, 0.05 ].min)
      end
    end

    private

    def run
      ActiveRecord::Base.connection_pool.with_connection do
        loop do
          break if @stop_requested

          work = begin
            @queue.pop(true)
          rescue ThreadError
            flush_counters
            sleep 0.1
            next
          end

          break if work == :shutdown

          process_work(work)
        end
      end
    rescue => e
      set_state :error
      @mutex.synchronize { @errors << e.message }
      log(:error, "Background worker crashed: #{e.message}")
    end

    def process_work(work)
      case work[:type]
      when :full_index
        return if on_cooldown?
        set_state :indexing
        @indexer.index_all
        @mutex.synchronize do
          @errors = @indexer.errors
          @last_full_reindex_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @reindex_count += 1
        end
        set_state :idle
      when :index_files
        set_state :indexing
        @indexer.index_files(work[:payload])
        @mutex.synchronize { @errors = @indexer.errors }
        set_state :idle
      when :flush
        flush_counters
      end
    end

    def on_cooldown?
      @mutex.synchronize do
        return false unless @last_full_reindex_at
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_full_reindex_at
        elapsed < REINDEX_COOLDOWN
      end
    end

    def flush_counters
      ids = @mutex.synchronize { @hit_count_buffer.shift(@hit_count_buffer.size) }
      if ids.any?
        Chunk.where(id: ids).update_all("hit_count = hit_count + 1")
      end

      search_count, reindex_count = @mutex.synchronize do
        counts = [ @search_count, @reindex_count ]
        @search_count = 0
        @reindex_count = 0
        counts
      end

      if search_count > 0
        current = Database::Metadata.get("total_searches").to_i
        Database::Metadata.set "total_searches", current + search_count
        Database::Metadata.set "last_search_at", Time.now.iso8601
      end

      if reindex_count > 0
        current = Database::Metadata.get("total_reindexes").to_i
        Database::Metadata.set "total_reindexes", current + reindex_count
        Database::Metadata.set "last_reindex_at", Time.now.iso8601
      end
    end

    def set_state(new_state)
      @mutex.synchronize { @state = new_state }
    end

    def log(level, message)
      @logger&.send(level, message)
    end
  end
end
