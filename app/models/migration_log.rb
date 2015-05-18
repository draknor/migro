class MigrationLog < ActiveRecord::Base

  enum log_type: [:error, :mapped]
  belongs_to :migration_run
  before_save :truncate_message

  default_scope { order('created_at ASC') }

  def error_count
    self.id_list.nil? ? 0 : self.id_list.split("\n").count
  end

  def add_id(id)
    if self.id_list.nil? || self.id_list.length == 0
      self.id_list = id.to_s if id.to_s.length < 255
    else
      new_list = self.id_list + "\n" + id.to_s
      self.id_list = new_list if new_list.length < 255
    end
  end

  def add_id!(id)
    add_id(id)
    save if self.id_list_changed?
  end

  def truncate_message
    puts "[debug] truncate_message"
    self.message = self.message.truncate(254) unless self.message.nil?
  end

end
