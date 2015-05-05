class AddIdListtoMigrationLog < ActiveRecord::Migration
  def change
    remove_column :migration_logs, :error_count
    add_column :migration_logs, :id_list, :text
  end
end
