if Rails.env != 'test' then
  Highrise::Base.site = Rails.application.secrets[:highrise][:site]
  Highrise::Base.user = Rails.application.secrets[:highrise][:token]
end