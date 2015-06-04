class MigrationLog < ActiveRecord::Base

  enum log_type: [:error, :mapped, :exception]
  belongs_to :migration_run
  before_save :truncate_message

  default_scope { order('created_at ASC') }
  scope :recent, ->{ last(25) }

  def error_count
    self.id_list.nil? ? 0 : self.id_list.split("\n").count
  end

  def add_id(id)
    if self.id_list.nil? || self.id_list.length == 0
      self.id_list = id.to_s if id.to_s.length < 255
    elsif self.id_list.length < 248
      new_list = self.id_list + "\n" + id.to_s
      if new_list.length < 248
        self.id_list = new_list
      else
        self.id_list = self.id_list + "\n" + "+more"
      end
    else
      # do nothing
    end
  end

  def add_id!(id)
    add_id(id)
    save if self.id_list_changed?
  end

  def truncate_message
    # puts "[debug] truncate_message"
    self.message = self.message.truncate(254) unless self.message.nil?
    self.target_before = self.target_before.truncate(65534) unless self.target_before.nil?
    self.target_after = self.target_after.truncate(65534) unless self.target_after.nil?
    self.source_before = self.source_before.truncate(65534) unless self.source_before.nil?
  end

end
