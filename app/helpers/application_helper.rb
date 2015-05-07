module ApplicationHelper

  def format_time(timestamp)
    timestamp.nil? ? '' : localize(timestamp.in_time_zone("Central Time (US & Canada)"), format: :simple)
  end
end
