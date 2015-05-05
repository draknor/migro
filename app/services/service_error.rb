class ServiceError

  attr_accessor :id, :name, :message
  def initialize(msg)
    @message = msg || ''
  end
end