module ActiveMerchant
  module Shipping
    class UPS
      # Determines the amount of time a shipment will take to be shipped from one location to another.
      # 
      # origin & destinaion - Location objects with at least the following:
      #   postal_code, 
      #   country
      #   residential? should be true if this is a residential address (i.e. :address_type => 'residential')
      # pickup_date - a Time/Date/DateTime object representing the date the package will be picked up by UPS
      # 
      # Additional information is required for international shipments, or for shipments with non-documents (i.e. most packages)
      # documents_only - true/false, default: false - shipment contains only documents with no commercial value 
      # total_packages - Fixnum, default: 1 - The number of packages in the shipment
      # shipment_weight_in_lbs - Float - The weight of the shipment in pounds
      # monetary_value - Moneyish [2] - The declared value of the shipment
      # maximum_list_size - Fixnum between 1 and 50, default: 35 - the maximum number of candidate locations you wish to receive if you provide an invalid origin or destination
      # 
      # Should the user provide an invalid origin or destination, a candidate list of possible origins or destinations 
      # will be returned in one or both of response.origin_candidates, response.destination_candidates. 
      # 
      # Restrictions: 
      # Please reference "Key Legal Restrictions for UPS OnLine Tools Time In Transit (TNT) Tool" in the docs
      # 
      # [1] UPS's Documentation: 
      # http://www.ups.com/e_comm_access/laServ?loc=en_US&CURRENT_PAGE=WELCOME&OPTION=TOOL_DOC&TOOL_ID=TimeNTransitXML
      # [2] Money(ish) (i.e. responds to to_money) from the Money gem
      def find_time_in_transit(origin, destination, pickup_date, shipment_weight_in_lbs = nil, total_packages = nil, monetary_value = nil, documents_only = false, maximum_list_size = nil, options={})
        #TODO: this argument list is really hairy... clean it up
        options = @options.merge(options)
        access_request = build_access_request
        time_request = build_time_in_transit_request(origin, destination, pickup_date, shipment_weight_in_lbs, total_packages, monetary_value, documents_only, maximum_list_size)
        response = commit(:time_in_transit, save_request(access_request + time_request), (options[:test] || false))
        parse_time_in_transit_response(response)
      end
      
      protected
      
      # Summary of document format: Page 26 of TNT_DeveloperGuide_12_20_07.pdf
      def build_time_in_transit_request(origin, destination, pickup_date, shipment_weight_in_lbs = nil, total_packages = nil, monetary_value = nil, documents_only = false, maximum_list_size = nil)
        xml_request = xml('TimeInTransitRequest') { |root|
          root << xml('Request') { |request|
            request << xml('RequestAction', 'TimeInTransit')
            # Not implemented: TransactionReference/*
          }
          root << xml('TransitFrom') {|from| from << address_artifact(origin) }
          root << xml('TransitTo') {|to| to << address_artifact(destination) }
          root << xml('PickupDate', pickup_date.strftime("%Y%m%d")) # YYYYMMDD
          if shipment_weight_in_lbs
            root << weight('ShipmentWeight', shipment_weight_in_lbs, 'LBS') #TODO: get the weight in its native format
          end
          if total_packages
            root << xml('TotalPackagesInShipment', total_packages)
          end
          if monetary_value
            root << money('InvoiceLineTotal', monetary_value.to_money)
          end
          if documents_only
            root << xml('DocumentsOnlyIndicator')
          end
          if maximum_list_size
            root << xml('MaximumListSize', maximum_list_size)
          end
        }
        
        xml_request.to_xml
      end
      
      def xml(*args)
        XmlNode.new(*args) { |x| yield(x) if block_given? }
      end
      
      def money(container_name, money)
        xml(container_name) { |container|
          container << xml('CurrencyCode', money.currency)
          container << xml('MonetaryValue', money.to_s)
        }
      end
      
      def weight(container_name, weight, code)
        xml(container_name) { |container|
          container << xml('UnitOfMeasurement') { |unit|
            unit << xml('Code', code)
            # Not implemented: Description
          }
          container << xml('Weight', weight)
        }
      end
      
      def address_artifact(location)
        xml('AddressArtifactFormat') { |address|
          # Not implemented: PoliticalDivision3
          address << xml('PoliticalDivision2', location.city) unless location.city.blank?
          address << xml('PoliticalDivision1', location.state) unless location.province.blank?
          address << xml('CountryCode', location.country.code(:alpha2))
          address << xml('PostcodePrimaryLow', location.postal_code) unless location.postal_code.blank?
          address << xml('ResidentialAddressIndicator') if location.residential?
        }
      end
      
      # Summary of document format: Pages 28-30 of TNT_DeveloperGuide_12_20_07.pdf
      def parse_time_in_transit_response(response)
        xml_hash = Hash.from_xml(response)['TimeInTransitResponse']
        success = response_hash_success?(xml_hash)
        
        unless success
          raise ActiveMerchantError, response_hash_message(xml_hash)
          #TODO: conform to the others
        end
        
        x_transit_response =  xml_hash['TransitResponse']
        
        # TODO: pretty much everything except the most common use-case. 
        # There's lots of cool stuff in there, like # of holidays and number of days in customs
        result = TimeInTransitResult.new(x_transit_response['Disclaimer'])
        
        if x_service_summary = x_transit_response['ServiceSummary']
          for x_summary in Array(x_service_summary)
            x_service = x_summary['Service']
            service_code = x_service['Code']
            service_name = x_service['Description']

            x_guaranteed = x_summary['Guaranteed']
            # The DeveloperGuide says that code should be "1" or "0".
            # However, the examples and the InterfaceSpecification use 'Y' and 'N', 
            # so we check for both
            guaranteed = ['1', 'Y'].include?(x_guaranteed['Code'])
            description = x_guaranteed['Description']

            x_arrival = x_summary['EstimatedArrival']
            s_date = x_arrival['Date']
            s_time = x_arrival['Time']
            days = x_arrival['BusinessTransitDays'].to_i

            time = Time.parse("#{s_date} #{s_time}") #TODO: take time-zones into account?

            result.services << TimeInTransitService.new(service_code, service_name, time, days, guaranteed, description)
          end 
        end
        
        if x_from_list = x_transit_response['TransitFromList']
          result.origin_candidates = build_candidate_list(x_from_list)
        end
        
        if x_to_list = x_transit_response['TransitToList']
          result.destination_candidates = build_candidate_list(x_to_list)
        end
        
        result
      end
      
      def build_candidate_list(x_list)
        result = []
        for x_candidate in Array(x_list['Candidate'])
          x_artifact = x_candidate['AddressArtifactFormat']
          result << AddressCandidate.new(
            x_artifact['PoliticalDivision1'],
            x_artifact['PoliticalDivision2'],
            x_artifact['PoliticalDivision3'],
            x_artifact['PostcodePrimaryLow'],
            x_artifact['PostcodePrimaryHigh'],
            x_artifact['PostcodeExtendedLow'],
            x_artifact['PostcodeExtendedHigh'],
            x_artifact['Country'],
            x_artifact['CountryCode']
          )
        end
        result
      end
      
    end
    
    # TODO: do these belong somewhere else?
    
    class TimeInTransitResult
      attr_reader :disclaimer, :services, :origin_candidates, :destination_candidates
      def initialize(disclaimer)
        @disclaimer = disclaimer
        @services = []
        @origin_candidates = []
        @destination_candidates = []
      end
    end
    
    class AddressCandidate
      attr_reader :political_division1, :political_division2, :political_division3
      alias_method :state, :political_division1
      alias_method :province, :political_division1
      alias_method :city, :political_division2
      alias_method :urbanization, :political_division3
      alias_method :town, :political_division3

      attr_reader :postcode_primary_low, :postcode_primary_high, :postcode_extended_low, :postcode_extended_high
      
      attr_reader :country, :country_code
      
      def initialize(political_division1, political_division2, political_division3, postcode_primary_low, postcode_primary_high, postcode_extended_low, postcode_extended_high, country, country_code)
        @political_division1, @political_division2, @political_division3, @postcode_primary_low, @postcode_primary_high, @postcode_extended_low, @postcode_extended_high, @country, @country_code = 
          political_division1, political_division2, political_division3, postcode_primary_low, postcode_primary_high, postcode_extended_low, postcode_extended_high, country, country_code
      end
    end
    
    class TimeInTransitService
      
      # TODO: this mapping is only possibly accurate for shipments from the US and
      # Canada. To get a full fidelity mapping, we'd need to look at service code,
      # origin country, and destination country
      TNT_TO_RSS_SERVICE_CODE_MAPPING = {
        '1DM' => '14', # UPS Next Day Air® Early A.M
        '1DA' => '01', # UPS Next Day Air®
        '1DP' => '13', # UPS Next Day Air Saver®
        '2DM' => '59', # UPS Second Day Air A.M.®
        '2DA' => '02', # UPS Second Day Air®
        '3DS' => '12', # UPS Three-Day Select® 
        'GND' => '03', # UPS Ground
        '1DMS' => '14', # UPS Next Day Air® Early A.M. (Saturday Delivery) #TODO: these 3 aren't true mappings:
        '1DAS' => '01', # UPS Next Day Air (Saturday Delivery)#TODO: these 3 aren't true mappings:
        '2DAS' => '59', # UPS Second Day Air (Saturday Delivery)#TODO: these 3 aren't true mappings:
        '24' => '01', # UPS Express  
        '19' => '02', # UPS Expedited 
        '01' => '07', # UPS Worldwide ExpressSM
        '09' => '07', # UPS Worldwide Express 
        '05' => '08', # UPS Worldwide ExpeditedSM
        '21' => '54', # UPS Worldwide Express Plus, UPS Express Early A.M. SM 
        '23' => '14', # UPS Express Early A.M. SM 
        '03' => '11', # UPS Standard
        '25' => '11', # UPS Standard  
        '68' => '11', # UPS Standard  
        '33' => '12', # UPS Three-Day Select®  
        '20' => '65', # UPS Express Saver   #TODO, not sure about this one.
        '28' => '65', # UPS Express Saver   #TODO: not sure
        '28' => '65', # UPS Worldwide Saver, UPS Express Saver  #TODO: not sure about this mapping
      }
      
      attr_reader :service_code, :service_name, :delivery_at, :business_days, :guaranteed, :description
      def initialize(service_code, service_name, delivery_at, business_days, guaranteed, description)
        @service_code, @service_name, @delivery_at, @business_days, @guaranteed, @description = 
          service_code, service_name, delivery_at, business_days, guaranteed, description
      end
      alias_method :guaranteed?, :guaranteed
      
      def ups_service_code
        TNT_TO_RSS_SERVICE_CODE_MAPPING[service_code]
      end
    end
    
  end
end