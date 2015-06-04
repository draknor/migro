class MigrationRun < ActiveRecord::Base

  enum status: [ :created, :preparing, :running, :completed_success, :completed_error, :canceled, :unknown, :queued, :aborted, :failed ]
  enum phase: [:test_only, :create_record, :load_history, :update_history, :catchup_all]
  before_save :update_max_records

  belongs_to :user
  belongs_to :source_system, class_name: 'System'
  belongs_to :destination_system, class_name: 'System'
  has_many :migration_logs

  validates_presence_of :source_system
  validates_presence_of :destination_system
  validates_presence_of :entity_type
  validates_presence_of :phase


  def update_max_records
    if all_records
      self[:max_records] = -1 if self[:max_records].nil?
    else
      self[:max_records] = record_list.split("\r\n").count
    end
  end

  def increment_record
    self.records_migrated = self.records_migrated.to_i + 1
  end

  def increment_record!
    increment_record
    save
  end

  def reset
    self.started_at = nil
    self.ended_at= nil
    self.records_migrated = nil
    self.abort_at = nil
    self[:max_records] = nil
    update_max_records
    self.created!
    self.migration_logs.each {|log| log.delete}
  end

  def abort
    if self.queued? || self.running?
      self.abort_at = Time.now
      save
    end
  end

  # t.timestamp :started_at
  # t.timestamp :ended_at
  # t.integer :source_system_id
  # t.integer :destination_system_id
  # t.integer :user_id
  # t.string :entity_type
  # t.integer :records_migrated
  # t.integer :max_records
  # t.integer :status, default: 0
  # t.string :name

end
