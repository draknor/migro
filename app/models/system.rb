class System < ActiveRecord::Base
  TYPES = [:highrise, :bullhorn]
  enum integration_type: TYPES

  after_initialize :after_system_init

  attr_reader :system_type

  def entities
    begin
      @system_type.entities
    rescue
      [ServiceError.new('API failed to retrieve entity list')]
    end
  end

  def account_info
    begin
      @system_type.account_info
    rescue
      ServiceError.new('API failed to retrieve account info')
    end
  end

  def search(entity,query,options ={})
    begin
      @system_type.search(entity,query,options={})
    rescue
      [ServiceError.new('API search failed')]
    end

  end

  def retrieve(entity,timestamp,page)
    begin
      @system_type.retrieve(entity,timestamp,page)
    rescue
      [ServiceError.new('API retrieval failed')]
    end

  end

  def get(entity,entity_id)
    return nil if entity.blank? || entity_id.blank?
    begin
      @system_type.get(entity,entity_id)
    rescue
      ServiceError.new('API get failed')
    end

  end

  def get_meta(entity)
    return [] if entity.blank?
    begin
      @system_type.get_meta(entity)
    rescue
      [ServiceError.new('API get_meta failed')]
    end
  end

  def get_option(option_type)
    return [] if option_type.blank?
    begin
      @system_type.get_option(option_type)
    rescue
      [ServiceError.new('API get_option failed')]
    end
  end

  def create(entity,attributes)
    begin
      @system_type.create(entity,attributes)
    rescue
      ServiceError.new('API create failed')
    end
  end

  def update(entity,id,attributes)
    begin
      @system_type.update(entity,id,attributes)
    rescue
      ServiceError.new('API update failed')
    end
  end

  def add_association(entity,id,assoc_entity,values)
    begin
      @system_type.add_association(entity,id,assoc_entity,values)
    rescue
      ServiceError.new('API add_association failed')
    end
  end


  def max_per_page
    @system_type.max_per_page
  end


  # Private methods #########################
  private
  def after_system_init
    case self.integration_type
      when :highrise.to_s
        @system_type = HighriseSystem
      when :bullhorn.to_s
        @system_type = BullhornSystem
      else
        @system_type = BaseSystem
    end
  end

end
