# frozen_string_literal: true

module SEPA
  PAIN_008_001_02 = 'pain.008.001.02'
  PAIN_008_002_02 = 'pain.008.002.02'
  PAIN_008_003_02 = 'pain.008.003.02'
  PAIN_001_001_03 = 'pain.001.001.03'
  PAIN_001_002_03 = 'pain.001.002.03'
  PAIN_001_003_03 = 'pain.001.003.03'
  PAIN_001_001_03_CH_02 = 'pain.001.001.03.ch.02'

  class Message
    include ActiveModel::Validations

    attr_reader :account, :grouped_transactions

    validates_presence_of :transactions
    validate do |record|
      unless record.account.valid?
        record.errors.add(:account, record.account.errors.full_messages)
      end
    end

    class_attribute :account_class, :transaction_class, :xml_main_tag, :known_schemas

    def initialize(account_options = {})
      @grouped_transactions = {}
      @account = account_class.new(account_options)
    end

    def add_transaction(options)
      transaction = transaction_class.new(options)
      unless transaction.valid?
        raise ArgumentError, transaction.errors.full_messages.join("\n")
      end

      @grouped_transactions[transaction_group(transaction)] ||= []
      @grouped_transactions[transaction_group(transaction)] << transaction
    end

    def transactions
      grouped_transactions.values.flatten
    end

    # @return [String] xml
    def to_xml(schema_name = known_schemas.first)
      raise SEPA::Error, errors.full_messages.join("\n") unless valid?
      unless schema_compatible?(schema_name)
        raise SEPA::Error, "Incompatible with schema #{schema_name}!"
      end

      builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |builder|
        builder.Document(xml_schema(schema_name)) do
          builder.__send__(xml_main_tag) do
            build_group_header(builder)
            build_payment_informations(builder)
          end
        end
      end

      validate_final_document!(builder.doc, schema_name)
      builder.to_xml
    end

    def amount_total(selected_transactions = transactions)
      selected_transactions.inject(0) { |sum, t| sum + t.amount }
    end

    def schema_compatible?(schema_name)
      unless known_schemas.include?(schema_name)
        raise ArgumentError, "Schema #{schema_name} is unknown!"
      end

      case schema_name
      when PAIN_001_002_03, PAIN_008_002_02, PAIN_001_001_03, PAIN_001_001_03_CH_02
        account.bic.present? && transactions.all? { |t| t.schema_compatible?(schema_name) }
      when PAIN_001_003_03, PAIN_008_003_02, PAIN_008_001_02
        transactions.all? { |t| t.schema_compatible?(schema_name) }
      end
    end

    # Set unique identifer for the message
    def message_identification=(value)
      unless value.is_a?(String)
        raise ArgumentError, 'message_identification must be a string!'
      end

      regex = %r{\A([A-Za-z0-9]|[\+|\?|/|\-|\:|\(|\)|\.|\,|\'|\ ]){1,35}\z}
      unless value.match(regex)
        raise ArgumentError, "message_identification does not match #{regex}!"
      end

      @message_identification = value
    end

    # Get unique identifer for the message (with fallback to a random string)
    def message_identification
      @message_identification ||= "SEPA-KING/#{SecureRandom.hex(11)}"
    end

    # Set creation date time for the message
    # p.s. Rabobank in the Netherlands only accepts the more restricted format [0-9]{4}[-][0-9]{2,2}[-][0-9]{2,2}[T][0-9]{2,2}[:][0-9]{2,2}[:][0-9]{2,2}
    def creation_date_time=(value)
      unless value.is_a?(String)
        raise ArgumentError, 'creation_date_time must be a string!'
      end

      regex = /[0-9]{4}[-][0-9]{2,2}[-][0-9]{2,2}(?:\s|T)[0-9]{2,2}[:][0-9]{2,2}[:][0-9]{2,2}/
      unless value.match(regex)
        raise ArgumentError, "creation_date_time does not match #{regex}!"
      end

      @creation_date_time = value
    end

    # Get creation date time for the message (with fallback to Time.now.iso8601)
    def creation_date_time
      @creation_date_time ||= Time.now.iso8601
    end

    # Returns the id of the batch to which the given transaction belongs
    # Identified based upon the reference of the transaction
    def batch_id(transaction_reference)
      grouped_transactions.each do |group, transactions|
        if transactions.select { |transaction| transaction.reference == transaction_reference }.any?
          return payment_information_identification(group)
        end
      end
    end

    def batches
      grouped_transactions.keys.collect { |group| payment_information_identification(group) }
    end

    private

    # @return {Hash<Symbol=>String>} xml schema information used in output xml
    def xml_schema(schema_name)
      unless schema_name == PAIN_001_001_03_CH_02
        return {
          xmlns: "urn:iso:std:iso:20022:tech:xsd:#{schema_name}",
          'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
          'xsi:schemaLocation': "urn:iso:std:iso:20022:tech:xsd:#{schema_name} #{schema_name}.xsd"
        }
      end

      {
        xmlns: 'http://www.six-interbank-clearing.com/de/pain.001.001.03.ch.02.xsd',
        'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation': 'http://www.six-interbank-clearing.com/de/pain.001.001.03.ch.02.xsd  pain.001.001.03.ch.02.xsd'
      }
    end

    def build_group_header(builder)
      builder.GrpHdr do
        builder.MsgId(message_identification)
        builder.CreDtTm(creation_date_time)
        builder.NbOfTxs(transactions.length)
        builder.CtrlSum('%.2f' % amount_total)
        builder.InitgPty do
          builder.Nm(account.name)
          if account.respond_to? :creditor_identifier
            builder.Id do
              builder.OrgId do
                builder.Othr do
                  builder.Id(account.creditor_identifier)
                end
              end
            end
          end
        end
      end
    end

    # Unique and consecutive identifier (used for the <PmntInf> blocks)
    def payment_information_identification(group)
      "#{message_identification}/#{grouped_transactions.keys.index(group) + 1}"
    end

    # Returns a key to determine the group to which the transaction belongs
    def transaction_group(transaction)
      transaction
    end

    def validate_final_document!(document, schema_name)
      xsd = Nokogiri::XML::Schema(File.read(File.expand_path("../../../lib/schema/#{schema_name}.xsd", __FILE__)))
      errors = xsd.validate(document).map(&:message)
      if errors.any?
        raise SEPA::Error, "Incompatible with schema #{schema_name}: #{errors.join(', ')}"
      end
    end
  end
end
