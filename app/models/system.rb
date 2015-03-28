class System < ActiveRecord::Base
  TYPES = [:highrise, :bullhorn]
  enum integration_type: TYPES



  after_initialize :after_system_init

  def entities
    begin
      @system_type.entities
    rescue
      ServiceError.new('API failed to retrieve entity list')
    end
  end

  def account_info
    begin
      @system_type.account_info
    rescue
      ServiceError.new('API failed to retrieve account info')
    end
  end

  def search(entity,query)
    begin
      @system_type.search
    rescue
      ServiceError.new('API search failed')
    end

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
