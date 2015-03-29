class HighriseSystem < BaseSystem

  @@entities = [
      :account, :comment, :company, :deal, :deal_category, :email, :group, :case, :membership,
      :note, :party, :person, :recording, :subject, :tag, :task, :task_category, :user
  ]


  def self.account_info
    # Hashie::Mash.new JSON.parse Highrise::Account.me.to_json
    JSON.parse Highrise::Account.me.to_json
  end


end