class System < ActiveRecord::Base
  has_many :entities
  TYPES = [:highrise, :bullhorn]
  enum integration_type: TYPES

  ENTITIES = {
      :highrise => [
          :account, :comment, :company, :deal, :deal_category, :email, :group, :case, :membership,
          :note, :party, :person, :recording, :subject, :tag, :task, :task_category, :user
      ],
      :bullhorn => [
        :appointment, :appointment_attendee, :business_sector, :candidate, :candidate_certification,
        :candidate_education, :candidate_reference, :candidate_work_history, :category, :client_contact,
        :client_corporation, :corporate_user, :corporation_department, :country, :custom_action, :job_order,
        :job_submission, :note, :note_entity, :placement, :placement_change_request, :placement_commission,
        :sendout, :skill, :specialty, :state, :task, :tearsheet, :tearsheet_recipient, :time_unit
      ]
  }


end
