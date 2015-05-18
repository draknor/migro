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
                WY: "Wyoming"
  }

  ZCONAPP = {
      'zconapp adt/prelude:' => 'adt/prelude',
      'zconapp amb:' => 'ambulatory',
      'zconapp anesthesia:' => 'anesthesia',
      'zconapp asap:' => 'asap',
      'zconapp beacon:' => 'beacon',
      'zconapp beaker' => 'beaker cp',
      'zconapp cadence:' => 'cadence',
      'zconapp claims:' => 'claims',
      'zconapp clarity:' => 'clarity',
      'zconapp client systems:' => 'client systems',
      'zconapp clin doc:' => 'clin doc',
      'zconapp cogito:' => 'cogito',
      'zconapp comm connect ip:' => 'community connect (ip)',
      'zconapp comm connect op:' => 'community connect (op)',
      'zconapp cupid:' => 'cupid',
      'zconapp data courier:' => 'data courier',
      'zconapp hb:' => 'hb',
      'zconapp him:' => 'him',
      'zconapp home health:' => 'home health',
      'zconapp interfaces:' => 'interfaces',
      'zconapp kaleidoscope:' => 'kaleidoscope',
      'zconapp mychart:' => 'mychart',
      'zconapp optime:' => 'optime',
      'zconapp order transmittal:' => 'order transmittal',
      'zconapp orders:' => 'orders',
      'zconapp pb:' => 'pb',
      'zconapp radiant:' => 'radiant',
      'zconapp security:' => 'security',
      'zconapp server systems:' => 'server systems',
      'zconapp stork:' => 'stork',
      'zconapp willow amb:' => 'willow amb',
      'zconapp willow ip:' => 'willow ip',
      'zconapp transplant/phoenix:' => 'transplant',
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


  def self.transform(system_type, entity, field, value='')
    # puts "[debug] transform: system_type: #{system_type}, field: #{field}, value: #{value}"
    new_value = nil
    if system_type.to_sym == :bullhorn
      # entity-specific fields
      if new_value.nil?
        new_value = case entity.to_sym
                      when :candidate
                      when :client_contact
                      when :company
                        case field.to_sym
                          when :customText10
                            {"bluetree's" => 'bluetree sow',
                             "client's"   => 'client sow'}[value.downcase] unless value.blank?
                        end
                    end
      end

      # cross-entity fields
      if new_value.nil?
        new_value = case field.to_sym
                      when :state
                        us_state = STATES[value.upcase.to_sym] unless value.blank?
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
      app = ZCONAPP[subject[:subject_field_label].downcase]
      unless app.blank?
        values = subject[:value].downcase.chars
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
        values = subject[:value].downcase.chars
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
end