class MigrationLog < ActiveRecord::Base

  enum log_type: [:error, :mapped]
  belongs_to :migration_run

  default_scope { order('created_at ASC') }

  def error_count
    self.id_list.nil? ? 0 : self.id_list.split("\n").count
  end

  def add_id(id)
    self.id_list = self.id_list.nil? ? id : self.id_list + "\n" + id
  end

  def add_id!(id)
    add_id(id)
    save
  end

end
