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


  def self.transform(system_type, field, value)
    # puts "[debug] transform: system_type: #{system_type}, field: #{field}, value: #{value}"

    new_value = case system_type.to_sym
                  when :highrise
                    case field.to_sym
                      when :state
                        us_state = STATES[value.to_sym] unless value.blank?
                        us_state.blank? ? value : us_state
                      when :customText10
                        {"bluetree's" => 'bluetree sow',
                         "client's"   => 'client sow'}[value.downcase] unless value.blank?
                      else
                        value
                    end
                end

    new_value
  end

end