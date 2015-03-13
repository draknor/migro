class HighriseSystem < BaseSystem

  @@entities = [
      :account, :comment, :company, :deal, :deal_category, :email, :group, :case, :membership,
      :note, :party, :person, :recording, :subject, :tag, :task, :task_category, :user
  ]


  def self.account_info
    Highrise::Account.me
  end


end