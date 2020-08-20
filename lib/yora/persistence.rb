require 'fileutils'
require_relative 'message'

module Yora
  module Persistence
    class SimpleFile
      include Message

      def initialize(node_id, node_address)
        @node_id, @node_address = node_id, node_address
        FileUtils.rm_r "data/#{node_id}", :force => true
        FileUtils.mkdir_p "data/#{node_id}"

        @log_path = "data/#{node_id}/log.txt"
        @metadata_path = "data/#{node_id}/metadata.txt"
        @snapshot_path = "data/#{node_id}/snapshot.txt"
      end

      def read_metadata
        metadata = {
          current_term: 0,
          voted_for: nil,
          cluster: { @node_id => @node_address }
        }
        if File.exist?(@metadata_path)
          metadata = deserialize(File.read(@metadata_path))
        end

        $stderr.puts "-- metadata = #{metadata}"

        metadata
      end

      def read_log_entries
        log_entries = []
        if File.exist?(@log_path)
          File.open(@log_path, 'r').each_line do |line|
            log_entries << deserialize(line, false)
          end
        end
        $stderr.puts "-- log_entries = #{log_entries}"

        log_entries
      end

      def read_snapshot
        snapshot = {
          last_included_index: 0,
          last_included_term: 0,
          data: {}
        }

        if File.exist?(@snapshot_path)
          snapshot = deserialize(File.read(@snapshot_path))
        end
        $stderr.puts "-- snapshot = #{snapshot}"

        snapshot
      end

      def save_metadata(current_term, voted_for, cluster)
        File.open(@metadata_path, 'w') do |f|
          f.puts(serialize(current_term: current_term, voted_for: voted_for, cluster: cluster))
        end
      end

      def save_log_entries(log_entries)
        File.open(@log_path, 'w') do |f|
          log_entries.each do |entry|
            f.puts(serialize(entry))
          end
        end
      end

      def save_snapshot(snapshot)
        File.open(@snapshot_path, 'w') do |f|
          f.puts(serialize(snapshot))
        end
      end
    end
  end
end
