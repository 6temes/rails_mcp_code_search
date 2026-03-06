require "active_record"
require "neighbor"
require "digest"
require "fileutils"

module RailsMcpCodeSearch
  module Database
    DATA_DIR = File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")), "rails-mcp-code-search")

    class << self
      def setup(project_path: Dir.pwd, db_path: nil)
        path = db_path || db_path_for(project_path)
        ensure_data_directory(File.dirname(path))

        Neighbor::SQLite.initialize!

        ActiveRecord::Base.establish_connection(
          adapter: "sqlite3",
          database: path,
          pool: 5,
          timeout: 5000
        )

        configure_pragmas
        create_schema
        Metadata.set "project_path", project_path

        File.chmod 0o600, path if File.exist?(path)

        path
      end

      def db_path_for(project_path)
        digest = Digest::SHA256.hexdigest(project_path)
        File.join(DATA_DIR, "#{digest}.db")
      end

      private

      def ensure_data_directory(dir)
        FileUtils.mkdir_p dir, mode: 0o700
        noindex = File.join(dir, ".noindex")
        FileUtils.touch noindex unless File.exist?(noindex)
      end

      def configure_pragmas
        ActiveRecord::Base.connection.execute "PRAGMA journal_mode=WAL"
        ActiveRecord::Base.connection.execute "PRAGMA synchronous=NORMAL"
        ActiveRecord::Base.connection.execute "PRAGMA cache_size=-64000"
      end

      def create_schema
        ActiveRecord::Schema.define do
          unless table_exists?(:chunks)
            create_table :chunks do |t|
              t.text :file_path, null: false
              t.integer :line_start, null: false
              t.integer :line_end, null: false
              t.text :chunk_type, null: false
              t.text :qualified_name
              t.text :content, null: false
              t.text :checksum, null: false
              t.binary :embedding
              t.integer :hit_count, default: 0
              t.timestamps
            end

            add_index :chunks, :file_path
            add_index :chunks, :checksum
            add_index :chunks, :hit_count, order: { hit_count: :desc }
          end

          unless table_exists?(:metadata)
            create_table :metadata, id: false do |t|
              t.text :key, null: false, primary_key: true
              t.text :value, null: false
            end
          end
        end
      end
    end

    class Metadata < ActiveRecord::Base
      self.table_name = "metadata"
      self.primary_key = "key"

      def self.get(key)
        find_by(key:)&.value
      end

      def self.set(key, value)
        upsert({ key:, value: value.to_s }, unique_by: :key)
      end
    end
  end
end
