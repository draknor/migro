class MappingService

  STATES = {    AK: "Alaska",
                AL: "Alabama",
                AR: "Arkansas",
                AS: "American Samoa",
                AZ: "Arizona",
                CA: "California",
                CO: "Colorado",
                CT: "Connecticut",
                DC: "District of Columbia",
                DE: "Delaware",
                FL: "Florida",
                GA: "Georgia",
                GU: "Guam",
                HI: "Hawaii",
                IA: "Iowa",
                ID: "Idaho",
                IL: "Illinois",
                IN: "Indiana",
                KS: "Kansas",
                KY: "Kentucky",
                LA: "Louisiana",
                MA: "Massachusetts",
                MD: "Maryland",
                ME: "Maine",
                MI: "Michigan",
                MN: "Minnesota",
                MO: "Missouri",
                MS: "Mississippi",
                MT: "Montana",
                NC: "North Carolina",
                ND: "North Dakota",
                NE: "Nebraska",
                NH: "New Hampshire",
                NJ: "New Jersey",
                NM: "New Mexico",
                NV: "Nevada",
                NY: "New York",
                OH: "Ohio",
                OK: "Oklahoma",
                OR: "Oregon",
                PA: "Pennsylvania",
                PR: "Puerto Rico",
                RI: "Rhode Island",
                SC: "South Carolina",
                SD: "South Dakota",
                TN: "Tennessee",
                TX: "Texas",
                UT: "Utah",
                VA: "Virginia",
                VI: "Virgin Islands",
                VT: "Vermont",
                WA: "Washington",
                WI: "Wisconsin",
                WV: "West Virginia",
                WY: "Wyoming",
                ON: "Ontario"
  }

  ZCONAPP = {
      'zconapp adt/prelude:' => 'grand central adt',
      'zconapp amb:' => 'ambulatory',
      'zconapp anesthesia:' => 'anesthesia',
      'zconapp asap:' => 'asap ed',
      'zconapp beacon:' => 'beacon oncology',
      'zconapp beaker:' => 'beaker cp',
      'zconapp cadence:' => 'cadence',
      'zconapp claims:' => 'claims',
      'zconapp clarity:' => 'clarity',
      'zconapp client systems:' => 'client systems',
      'zconapp clin doc:' => 'clin doc',
      'zconapp cogito:' => 'cogito',
      'zconapp comm connect ip:' => 'community connect (ip)',
      'zconapp comm connect op:' => 'community connect (op)',
      'zconapp cupid:' => 'cupid cvis',
      'zconapp data courier:' => 'data courier',
      'zconapp hb:' => 'hospital billing',
      'zconapp him:' => 'him',
      'zconapp home health:' => 'home health',
      'zconapp interfaces:' => 'bridges interfaces',
      'zconapp kaleidoscope:' => 'kaleidoscope',
      'zconapp mychart:' => 'mychart',
      'zconapp optime:' => 'optime or',
      'zconapp order transmittal:' => 'order transmittal',
      'zconapp orders:' => 'orders',
      'zconapp pb:' => 'professional billing',
      'zconapp radiant:' => 'radiant',
      'zconapp security:' => 'security',
      'zconapp server systems:' => 'server systems',
      'zconapp stork:' => 'stork',
      'zconapp willow amb:' => 'willow amb',
      'zconapp willow ip:' => 'willow ip',
      'zconapp transplant/phoenix:' => 'phoenix transplant',
      'zconapp tapestry:' => 'tapestry'
  }

  ZCONROLE = {
      'zconrole analyst:' => 'analyst',
      'zconrole ct:' => 'ct',
      'zconrole director:' => 'director',
      'zconrole executive:' => 'executive',
      'zconrole instructional designer:' => 'id',
      'zconrole manager:' => 'manager',
      'zconrole pm:' => 'pm',
      'zconrole tm:' => 'training manager'
  }

  DEAL_CONTACT_OWNER = {
      4308269 => 232430573,
      4015916 => 221370879,
      4325100 => 214123278,
      4325092 => 214123278,
      4325082 => 214123278,
      4285570 => 214123278,
      4060336 => 202328115,
      4262179 => 213784704,
      4282290 => 213784704,
      3756200 => 213784704,
      4282688 => 213784704,
      4176560 => 213784704,
      4176640 => 213784704,
      4304564 => 177009010,
      4274895 => 185431194,
      4281851 => 186213948,
      4257679 => 186213948,
      4315814 => 169267720,
      4323083 => 198843011,
      4334219 => 198843011,
      4281319 => 169267720,
      4281339 => 169267720,
      4334210 => 198843011,
      4334201 => 198843011,
      4334189 => 198843011,
      4027061 => 221515780,
      4305592 => 229278925,
      4312334 => 233247313,
      4315758 => 194241821,
      4308559 => 232697310,
      4308551 => 165376530,
      4312514 => 192751020,
      4247504 => 197755914,
      4122245 => 197755914,
      4220823 => 205416706,
      4289375 => 206396689,
      4255611 => 206396689,
      4255620 => 206396689,
      4255623 => 206396689,
      4110446 => 212089246,
      4273089 => 214517757,
      4336859 => 214517596,
      4300963 => 232213859,
      4300956 => 232213859,
      4300958 => 232213859,
      4324638 => 232213859,
      4200442 => 219431395,
      4082776 => 226920035,
      4284394 => 226920035,
      4239828 => 219431395,
      4292417 => 219431395,
      4258971 => 225429300,
      4148741 => 226540533,
      4327798 => 177009172,
      4328426 => 232988610,
      4220823 => 205416706,
      4274668 => 232302105,
      4190932 => 187358265,
      4316276 => 225448619,
      4266748 => 188541458,
      4206755 => 188541458,
      4206753 => 188541458,
      4282547 => 210169774,
      4310802 => 210169774,
      4219664 => 188541458,
      4258962 => 230572967,
      4295726 => 219625039,
      4254519 => 221023327
  }

  DEFAULT_COMPANY = 234777598

  DEFAULT_CONTACT = 234766637

  def self.transform(system_type, entity, field, value='')
    # puts "[debug] transform: system_type: #{system_type}, field: #{field}, value: #{value}"
    new_value = nil
    if system_type.to_sym == :bullhorn
      # entity-specific fields
      if new_value.nil?
        new_value = case entity.to_sym
                      when :candidate
                        case field.to_sym
                          when :employmentPreference
                            {
                              "local only" => "Direct Hire (HCO) - Local Only",
                              "open to relocation" => "Direct Hire (HCO) - Will Relocate",
                              "not interested" => "No FTE Roles",
                              "yes" => "Salaried Roles",
                              "no" => "No Salaried Roles",
                            }[value.strip.downcase] unless value.blank?
                          when :customText15
                            {
                              "consultant" => "Full-Time Hourly Consultant",
                              "consultant (pt)" => "Part-Time Hourly Consultant",
                              "former internal" => "Former Internal",
                              "inactive internal" => "Former Internal",
                              "inactive consultant" => "Former Consultant",
                              "internal" => "Active Internal",
                              "internal consultant" => "Salaried Consultant",
                              "no" => ''
                            }[value.strip.downcase] unless value.blank?
                          when :customText16
                            {
                              "w2 (30/20)" => "w2 - 30/20",
                              "w2 (33/23)" => "w2 - 33/23",
                              "1099 (33/23)" => "1099 - 33/23",
                              "1099 (30/20)" => "1099 - 30/20",
                              "c2c" => "c2c",
                            }[value.strip.downcase] unless value.blank?
                        end

                      when :client_contact
                      when :client_corporation
                        case field.to_sym
                          when :customText10
                            {"bluetree's" => 'bluetree sow',
                             "client's"   => 'client sow'}[value.downcase] unless value.blank?
                        end
                      when :job_order
                        case field.to_sym
                          when :employmentType
                            if value[0] == '0' || value[0] == '1'
                              'Other'
                            elsif value.include?("(FTE)")
                              'Permanent - FTE'
                            elsif value.include?("(C2C)")
                              'Contract (C2C)'
                            else
                              'Contract'
                            end
                          when :status
                            {
                                '0' => "Drafting Proposal",
                                '1' => "Proposal Submitted",
                                '2' => "Prospect",
                                '3' => "Confirmed",
                                '4' => "Candidate Submitted",
                                '5' => "Interviewing Candidate",
                                '6' => "Contracting"
                            }[value[0]] unless value.blank?
                          when :salaryUnit
                            {
                                'hour' => "Per Hour",
                                'day' => "Per Day",
                                'month' => "Per Month",
                                'year' => "Per Year",
                                'fixed' => "Fixed Bid"
                            }[value] unless value.blank?
                        end
                    end
      end

      # cross-entity fields
      if new_value.nil?
        new_value = case field.to_sym
                      when :state
                        us_state = STATES[value.strip.upcase.to_sym] unless value.blank?
                        us_state.blank? ? value : us_state
                      when :countryID
                        value.blank? ? 'United States' : value
                    end
      end
    end

    new_value.nil? ? value : new_value
  end

  def self.map_highrise_apps(subject_datas)
    apps = {}
    subject_datas.each do |subject|
      app = ZCONAPP[subject[:subject_field_label].strip.downcase]
      unless app.blank?
        values = subject[:value].strip.downcase.chars
        [:p, :c, :q, :t].each do |pref|
          if values.include?(pref.to_s)
            apps[pref] ||= []
            apps[pref] << app
            values.delete(pref.to_s)
          end
        end
        if values.count>0
          apps[:unknown] ||= []
          apps[:unknown] << app + ': ' + values.join('')
        end
      end
    end
    apps
  end

  def self.map_highrise_roles(subject_datas)
    roles = {}
    subject_datas.each do |subject|
      role = ZCONROLE[subject[:subject_field_label].downcase]
      unless role.blank?
        values = subject[:value].strip.downcase.chars
        [:p, :q, :e, :s].each do |pref|
          if values.include?(pref.to_s)
            roles[pref] ||= []
            roles[pref] << role
            values.delete(pref.to_s)
          end
        end
        if values.count>0
          roles[:unknown] ||= []
          roles[:unknown] << role + ': ' + values.join('')
        end
      end
    end
    roles
  end

  def self.get_hr_deal_owner(deal_id)
    owner = DEAL_CONTACT_OWNER[deal_id.to_i]
    owner ? owner : DEFAULT_CONTACT
  end

end