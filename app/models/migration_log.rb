class MigrationLog < ActiveRecord::Base

  enum log_type: [:error, :mapped]
  belongs_to :migration_run
  before_save :truncate_message

  default_scope { order('created_at ASC') }

  def error_count
    self.id_list.nil? ? 0 : self.id_list.split("\n").count
  end

  def add_id(id)
    self.id_list = self.id_list.nil? ? id.to_s : self.id_list + "\n" + id.to_s
  end

  def add_id!(id)
    add_id(id)
    save
  end

  def truncate_message
    puts "[debug] truncate_message"
    self.message = self.message.truncate(254) unless self.message.nil?
  end

end
