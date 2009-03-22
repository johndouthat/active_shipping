module ActiveMerchant
  module Shipping
    class UPS
      AV_DISCLAIMER = "NOTICE: UPS assumes no liability for the information provided by the address validation functionality.  The address validation functionality does not support the identification or verification of occupants at an address."
      
      # Validates a combination of City, State, and Postal code to ensure no shipping delays due to mis-typed or otherwise inaccurate data
      # 
      # Input: a Location object containing any combination of City, State, and Postal code, except State alone.
      # Returns an array of 0-10 ValidatedAddress objects, sorted in descending quality order and ascending rank order
      # or raises an ActiveMerchantError on error
      #  
      # In cases where no city/state/postal code combinations are found, returns an empty array.
      # 
      # usage:
      # include ActiveMerchant::Shipping
      # ups = UPS.new(...)
      # 
      # # Minimal input:
      # x = ups.validate_address(Location.new(:zip => '90210'))
      # => [#<ValidatedAddress:0x17fcbe0 @state_province_code="CA", @quality="0.9700", @city="BEVERLY HILLS", @postal_code_high_end="90213", @rank="1", @postal_code_low_end="90209">]
      # 
      # # Valid input:
      # >> x = ups.validate_address(Location.new(:state => 'LA', :zip => '70802'))
      # => [#<ValidatedAddress:0x1981a10 @state_province_code="LA", @quality="0.9900", @city="BATON ROUGE", @postal_code_high_end="70823", @rank="1", @postal_code_low_end="70801">]
      # 
      # # Invalid State:
      # >> x = ups.validate_address(Location.new(:state => 'CA', :zip => '70802'))
      # => [#<ValidatedAddress:0x1900fa0 @state_province_code="LA", @quality="0.7400", @city="BATON ROUGE", @postal_code_high_end="70823", @rank="1", @postal_code_low_end="70801">]
      # 
      # # Invalid State:
      # >> x = ups.validate_address(Location.new(:state => 'CO', :zip => '90210'))
      # => [#<ValidatedAddress:0x1848dd8 @state_province_code="CA", @quality="0.7400", @city="BEVERLY HILLS", @postal_code_high_end="90213", @rank="1", @postal_code_low_end="90209">]
      #
      # You must display the following notice, or such other language provided by UPS from time to time, in
      # reasonable proximity to the Address Validation input and output information screens:
      # +AV_DISCLAIMER+
      # 
      # Please refer to the documentation for any additional requirements and restrictions.
      # 
      # Documentation: 
      # http://www.ups.com/e_comm_access/laServ?loc=en_US&CURRENT_PAGE=WELCOME&OPTION=TOOL_DOC&TOOL_ID=AddrValidateXML
      def validate_address(location, options = {})
        #TODO: USPS also has an address validation api. Ensure if/when that API is written, we use the same signature
        options = @options.merge(options)
        access_request = build_access_request
        av_request = build_av_request(location)
        response = commit(:address_validation, save_request(access_request + av_request), (options[:test] || false))
        parse_av_response(response)
      end
      
      protected
      
      def build_av_request(location)
        xml_request = xml('AddressValidationRequest') { |root|
          root << xml('Request') { |request|
            request << xml('RequestAction', 'AV')
            # Not implemented: TransactionReference/*
          }
          root << xml('Address') { |address|
            #TODO: ensure the location has the necessary fields set before sending off to UPS?
            address << xml('City', location.city) unless location.city.blank?
            address << xml('StateProvinceCode', location.state) unless location.state.blank?
            address << xml('PostalCode', location.zip) unless location.zip.blank?
          }
        }
        xml_request.to_xml
      end
      
      def parse_av_response(response)
        xml_hash = ActiveMerchant.parse_xml(response)['AddressValidationResponse']
        success = response_hash_success?(xml_hash)
        
        unless success
          raise ActiveMerchantError, response_hash_message(xml_hash)
          #TODO: conform to the others
        end
        
        results = []
        for x_result in ary(xml_hash['AddressValidationResult'])
          results << ValidatedAddress.new(
            x_result['Rank'].to_i,
            x_result['Quality'].to_f,
            x_result['Address']['City'],
            x_result['Address']['StateProvinceCode'],
            x_result['PostalCodeLowEnd'],
            x_result['PostalCodeHighEnd']
          )
        end
        results
      end
      
      def ary(val)
        if Hash === val
          [val]
        else
          Array(val)
        end
      end
      
      #  City, State, Postal code range, Quality (Float between 0 and 1), and Rank.
      class ValidatedAddress
        attr_reader :rank, :quality, :city, :state_province_code, :postal_code_low_end, :postal_code_high_end
        def initialize(rank, quality, city, state_province_code, postal_code_low_end, postal_code_high_end)
          @rank, @quality, @city, @state_province_code, @postal_code_low_end, @postal_code_high_end =
            rank, quality, city, state_province_code, postal_code_low_end, postal_code_high_end
        end
        alias_method :state, :state_province_code
        alias_method :province, :state_province_code
        alias_method :zip_low, :postal_code_low_end
        alias_method :zip_high, :postal_code_high_end
      end
      
    end
  end
end