require 'csv'

namespace :export do
  desc "export logs"
  task :logs,[:file, :run_id] => :environment do |t,args|
    CSV.open( args.file, 'w' ) do |writer|
      writer << ["Run ID", "Run Name", "Log Type", "Log DateTime", "Message", "Source ID", "Target ID", "Error ID List"]
      run = MigrationRun.find(args.run_id)
      run.migration_logs.each do |log|
        writer << [run.id, run.name, log.log_type, log.created_at.iso8601, log.message, log.source_id, log.target_id, log.id_list.to_s.gsub("\n","|")]
      end
    end
  end

  desc "export all logs"
  task :all_logs,[:file] => :environment do |t,args|
    CSV.open( args.file, 'w' ) do |writer|
      writer << ["Run ID", "Run Name", "Log Type", "Log DateTime", "Message", "Source ID", "Target ID", "Error ID List"]
      MigrationRun.all.each do |run|
        run.migration_logs.each do |log|
          writer << [run.id, run.name, log.log_type, log.created_at.iso8601, log.message, log.source_id, log.target_id, log.id_list.to_s.gsub("\n","|")]
        end
      end
    end
  end

end
