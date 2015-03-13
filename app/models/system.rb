class System < ActiveRecord::Base
  TYPES = [:highrise, :bullhorn]
  enum integration_type: TYPES


end
