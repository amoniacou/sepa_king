# frozen_string_literal: true

module SEPA
  class Account
    include ActiveModel::Validations
    extend Converter

    ALLOWED_CHARGES = %w[DEBT SHAR SLEV].freeze

    attr_accessor :name, :iban, :bic, :charge_bearer, :creditor_identifier, :country_code, :currency
    convert :name, to: :text

    validates_length_of :name, within: 1..70
    validates_with BICValidator, IBANValidator, message: '%{value} is invalid'
    validates_inclusion_of :charge_bearer, in: ALLOWED_CHARGES, allow_nil: true
    validates_presence_of :country_code, :currency, :creditor_identifier

    def initialize(attributes = {})
      attributes.each do |name, value|
        public_send("#{name}=", value)
      end
    end
  end
end
