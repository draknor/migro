class BullhornSystem < BaseSystem

  @@conn_options = {

  }

  @@client ||= Bullhorn::Rest::Client.new(
      username: Rails.application.secrets[:bullhorn][:username],
      password: Rails.application.secrets[:bullhorn][:password],
      client_id: Rails.application.secrets[:bullhorn][:client_id],
      client_secret: Rails.application.secrets[:bullhorn][:client_secret],
      auth_host: Rails.application.secrets[:bullhorn][:auth_host],
      rest_host: Rails.application.secrets[:bullhorn][:rest_host]
  )

  @@entities = [
      :appointment, :appointment_attendee, :business_sector, :candidate, :candidate_certification,
      :candidate_education, :candidate_reference, :candidate_work_history, :category, :client_contact,
      :client_corporation, :corporate_user, :corporation_department, :country, :custom_action, :job_order,
      :job_submission, :note, :note_entity, :placement, :placement_change_request, :placement_commission,
      :sendout, :skill, :specialty, :state, :task, :tearsheet, :tearsheet_recipient, :time_unit

  ]


  def self.account_info
    # @@client.settings
    JSON.parse @@client.settings.data.to_json
  end

end