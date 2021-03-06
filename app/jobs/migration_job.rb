class MigrationJob < ActiveJob::Base
  queue_as :default

  def perform(migration_run_id)
    run = MigrationRun.find(migration_run_id)
    migration = MigrationService.new(run)
    begin
      migration.run
    rescue => e
      migration.rescue_after_error(e)
    end
  end


end
