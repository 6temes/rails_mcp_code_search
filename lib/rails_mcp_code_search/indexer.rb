require "open3"
require "digest"

module RailsMcpCodeSearch
  class Indexer
    INCLUDE_PATTERNS = %w[**/*.rb **/*.erb **/*.js **/*.ts **/*.yml **/*.yaml **/*.md].freeze
    EXCLUDE_PATTERNS = %w[vendor/ node_modules/ tmp/ log/ .git/].freeze
    BATCH_SIZE = 50

    NotAGitRepo = Class.new(StandardError)

    attr_reader :errors

    def initialize(embedding_adapter:, project_path: Dir.pwd, logger: nil)
      @embedding_adapter = embedding_adapter
      @project_path = File.realpath(project_path)
      @logger = logger
      @errors = []
    end

    def index_all
      @errors = []
      files = discover_files
      return if files.empty?

      process_files(files)
      update_metadata
    end

    def index_files(file_paths)
      @errors = []
      safe_paths = file_paths.select { valid_path?(_1) }
      process_files(safe_paths)
    end

    def changed_files
      @_changed_files_cache ||= {}
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if @_changed_files_cache[:at] && (now - @_changed_files_cache[:at]) < 3
        return @_changed_files_cache[:files]
      end

      stdout, _, status = Open3.capture3("git", "diff", "--name-only", "HEAD", chdir: @project_path)
      files = status.success? ? stdout.lines.map(&:strip).select { valid_path?(_1) } : []

      @_changed_files_cache = { files:, at: now }
      files
    end

    def discover_files
      tracked = git_ls_files
      untracked = git_ls_files("--others", "--exclude-standard")
      all_files = (tracked + untracked).uniq

      all_files.select { include_file?(_1) && valid_path?(_1) }
    end

    private

    def git_ls_files(*args)
      stdout, stderr, status = Open3.capture3("git", "ls-files", *args, chdir: @project_path)
      raise NotAGitRepo, "Not a git repository: #{@project_path}" unless status.success?
      stdout.lines.map(&:strip)
    end

    def include_file?(path)
      return false if EXCLUDE_PATTERNS.any? { path.start_with?(_1) || path.include?("/#{_1}") }
      INCLUDE_PATTERNS.any? { File.fnmatch?(_1, path, File::FNM_PATHNAME) }
    end

    def valid_path?(path)
      full_path = File.join(@project_path, path)
      return false unless File.exist?(full_path)
      real = File.realpath(full_path)
      real.start_with?(@project_path)
    rescue Errno::ENOENT
      false
    end

    def process_files(files)
      # Remove chunks for deleted files
      existing_paths = Chunk.distinct.pluck(:file_path)
      deleted = existing_paths - files
      Chunk.where(file_path: deleted).delete_all if deleted.any?

      chunks_to_embed = []

      files.each do |file_path|
        full_path = File.join(@project_path, file_path)
        source = File.read(full_path, encoding: "utf-8")

        unless source.valid_encoding?
          @errors << { file: file_path, error: "Invalid UTF-8 encoding" }
          next
        end

        file_checksum = Digest::SHA256.hexdigest(source)

        # Skip unchanged files
        existing = Chunk.where(file_path:).first
        next if existing && existing.checksum == file_checksum

        # Remove old chunks for this file
        Chunk.where(file_path:).delete_all

        parsed = parse_file(file_path, source)
        next if parsed.empty?

        parsed.each do |result|
          chunk_checksum = Digest::SHA256.hexdigest(result.content)
          chunk = Chunk.create!(
            file_path:,
            line_start: result.line_start,
            line_end: result.line_end,
            chunk_type: result.chunk_type,
            qualified_name: result.qualified_name,
            content: result.content,
            checksum: file_checksum
          )
          chunks_to_embed << chunk
        end

        # Batch embed
        if chunks_to_embed.size >= BATCH_SIZE
          embed_batch(chunks_to_embed)
          chunks_to_embed = []
        end
      rescue => e
        @errors << { file: file_path, error: e.message }
        log(:warn, "Error indexing #{file_path}: #{e.message}")
      end

      embed_batch(chunks_to_embed) if chunks_to_embed.any?
    end

    def parse_file(file_path, source)
      if file_path.end_with?(".rb")
        RubyParser.parse(source, file_path:)
      elsif file_path.end_with?(".erb")
        ErbParser.parse(source, file_path:)
      else
        SlidingWindowParser.parse(source, file_path:)
      end
    end

    def embed_batch(chunks)
      return if chunks.empty?
      texts = chunks.map(&:content)
      vectors = @embedding_adapter.embed(texts)

      chunks.each_with_index do |chunk, i|
        chunk.update!(embedding: vectors[i])
      end

      GC.start
    rescue => e
      @errors << { file: "batch_embed", error: e.message }
      log(:warn, "Embedding batch failed: #{e.message}")
    end

    def update_metadata
      Database::Metadata.set "last_reindex_at", Time.now.iso8601
      Database::Metadata.set "embedding_provider", @embedding_adapter.class.name.split("::").last
      Database::Metadata.set "embedding_dimensions", @embedding_adapter.dimensions
    end

    def log(level, message)
      @logger&.send(level, message)
    end
  end
end
