class System < ActiveRecord::Base
  TYPES = [:highrise, :bullhorn]
  enum integration_type: TYPES

  def entities
    case self.integration_type
    when :highrise.to_s
      HighriseSystem.entities
    when :bullhorn.to_s
      BullhornSystem.entities
    else
      nil
    end
  end

  def account_info
    begin
      case self.integration_type
        when :highrise.to_s
          HighriseSystem.account_info
        when :bullhorn.to_s
          BullhornSystem.account_info
        else
          nil
      end
    rescue
      ServiceError.new('API failed to retrieve account info')
    end
  end

end
