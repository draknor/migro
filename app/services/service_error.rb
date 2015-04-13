class ServiceError

  attr_accessor :id, :name
  def initialize(msg)
    @message = msg || ''
  end
end