class AddErrorCountToMigrationLog < ActiveRecord::Migration
  def change
    add_column :migration_logs, :error_count, :integer, :default => 1
  end
end
