module ApplicationHelper

  def format_time(timestamp)
    timestamp.nil? ? '' : localize(timestamp, format: :simple)
  end
end
