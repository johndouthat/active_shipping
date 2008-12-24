module ActiveMerchant
  module Shipping
    class UPS < Carrier
      cattr_accessor :default_options
      cattr_reader :name
      @@name = "UPS"
      
      TEST_DOMAIN = 'wwwcie.ups.com'
      LIVE_DOMAIN = 'www.ups.com'
      
      RESOURCES = {
        :rates => '/ups.app/xml/Rate',
        :track => '/ups.app/xml/Track',
        :time_in_transit => '/ups.app/xml/TimeInTransit',
        :address_validation => '/ups.app/xml/AV',
      }
      
      USE_SSL = {
        :rates => true,
        :track => true,
        :time_in_transit => true,
        :address_validation => true,
      }
      
      def requirements
        [:key, :login, :password]
      end
      
      protected
      def build_access_request
        xml_request = XmlNode.new('AccessRequest') do |access_request|
          access_request << XmlNode.new('AccessLicenseNumber', @options[:key])
          access_request << XmlNode.new('UserId', @options[:login])
          access_request << XmlNode.new('Password', @options[:password])
        end
        xml_request.to_xml
      end
      
      def response_hash_success?(xml_hash)
        xml_hash['Response']['ResponseStatusCode'] == '1'
      end
      
      def response_hash_message(xml_hash)
        response_hash_success?(xml_hash) ?
          xml_hash['Response']['ResponseStatusDescription'] :
          xml_hash['Response']['Error']['ErrorDescription']
      end
      
      def commit(action, request, test = false)
        http = Net::HTTP.new((test ? TEST_DOMAIN : LIVE_DOMAIN),
                              (USE_SSL[action] ? 443 : 80 ))
        http.use_ssl = USE_SSL[action]
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE if USE_SSL[action]
        response = http.start do |http|
          http.post RESOURCES[action], request
        end
        response.body
      end
      
      def xml(*args)
        XmlNode.new(*args) { |x| yield(x) if block_given? }
      end
      
    end
  end
end

require 'active_shipping/shipping/carriers/ups/rate_and_service_selection'
require 'active_shipping/shipping/carriers/ups/tracking'
require 'active_shipping/shipping/carriers/ups/time_in_transit'
require 'active_shipping/shipping/carriers/ups/address_validation'