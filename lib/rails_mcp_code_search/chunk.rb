module RailsMcpCodeSearch
  class Chunk < ActiveRecord::Base
    self.table_name = "chunks"

    has_neighbors :embedding
  end
end
