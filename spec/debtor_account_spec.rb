# frozen_string_literal: true

require 'spec_helper'

describe SEPA::DebtorAccount do
  it 'should initialize a new account' do
    expect(
      SEPA::DebtorAccount.new(name: 'Gläubiger GmbH',
                              bic: 'BANKDEFFXXX',
                              iban: 'DE87200500001234567890',
                              creditor_identifier: 'DE98ZZZ09999999999',
                              country_code: 'DE',
                              currency: 'EUR')
    ).to be_valid
  end
end
