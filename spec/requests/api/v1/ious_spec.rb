# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 IOUs', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  let(:account) do
    family.accounts.create!(
      name: 'Checking',
      balance: 1000,
      currency: 'USD',
      owner: user,
      accountable: Depository.create!
    )
  end

  let!(:client_fee) do
    family.ious.create!(
      direction: 'owed_to_me',
      person: 'Ravi',
      description: 'Website design',
      amount: 1500,
      due_on: Date.current + 5,
      account: account
    )
  end

  let!(:dinner) do
    family.ious.create!(direction: 'i_owe', person: 'Maya', description: 'Dinner split', amount: 40)
  end

  path '/api/v1/ious' do
    get 'List IOUs' do
      tags 'IOUs'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      parameter name: :direction, in: :query, required: false, schema: { type: :string, enum: %w[owed_to_me i_owe] }
      parameter name: :status, in: :query, required: false, schema: { type: :string, enum: %w[open settled] }
      parameter name: :page, in: :query, required: false, schema: { type: :integer }
      parameter name: :per_page, in: :query, required: false, schema: { type: :integer }

      response '200', 'IOUs listed' do
        schema '$ref' => '#/components/schemas/IouCollection'

        let(:status) { 'open' }

        run_test!
      end

      response '422', 'unknown filter value' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:status) { 'maybe' }

        run_test!
      end
    end

    post 'Create an IOU' do
      tags 'IOUs'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/IouRequest' }

      response '201', 'IOU created' do
        schema '$ref' => '#/components/schemas/Iou'

        let(:body) do
          { iou: { direction: 'owed_to_me', person: 'Ana', description: 'Logo work', amount: '250', due_on: (Date.current + 7).iso8601, account_id: account.id } }
        end

        run_test!
      end

      response '422', 'validation error' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { iou: { direction: 'owed_to_me', person: 'Ana', amount: '-5' } } }

        run_test!
      end
    end
  end

  path '/api/v1/ious/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'IOU ID'

    get 'Retrieve an IOU' do
      tags 'IOUs'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'IOU retrieved' do
        schema '$ref' => '#/components/schemas/Iou'

        let(:id) { client_fee.id }

        run_test!
      end

      response '404', 'IOU not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end

    patch 'Update an IOU' do
      tags 'IOUs'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/IouRequest' }

      response '200', 'IOU updated' do
        schema '$ref' => '#/components/schemas/Iou'

        let(:id) { client_fee.id }
        let(:body) { { iou: { amount: '1800' } } }

        run_test!
      end
    end

    delete 'Delete an IOU' do
      tags 'IOUs'
      security [ { apiKeyAuth: [] } ]

      response '204', 'IOU deleted; transactions from its payments stay' do
        let(:id) { dinner.id }

        run_test!
      end
    end
  end

  path '/api/v1/ious/{id}/payments' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'IOU ID'

    post 'Record a payment' do
      tags 'IOUs'
      description 'Creates a transaction in the account: income for owed_to_me, an expense for i_owe. ' \
                  'Returns the IOU with its payments.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          amount: { type: :string, description: "Defaults to what's left; can't be more than that" },
          date: { type: :string, format: :date, description: 'Defaults to today' },
          account_id: { type: :string, format: :uuid, description: "Defaults to the IOU's account" }
        }
      }

      response '201', 'payment recorded' do
        schema '$ref' => '#/components/schemas/Iou'

        let(:id) { client_fee.id }
        let(:body) { { amount: '500', date: Date.current.iso8601, account_id: account.id } }

        run_test!
      end

      response '422', 'no account, or more than what is left' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { dinner.id }
        let(:body) { { amount: '10' } }

        run_test!
      end
    end
  end
end
