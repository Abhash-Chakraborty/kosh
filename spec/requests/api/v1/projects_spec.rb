# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 Projects', type: :request do
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

  let!(:trip) do
    family.projects.create!(name: 'Lisbon in May', kind: 'trip', budget: 2000, start_on: Date.current - 10, end_on: Date.current - 3)
  end

  let!(:hotel) do
    account.entries.create!(name: 'Hotel', date: Date.current - 9, amount: 480, currency: 'USD', entryable: Transaction.new)
  end

  path '/api/v1/projects' do
    get 'List projects' do
      tags 'Projects'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      parameter name: :status, in: :query, required: false, schema: { type: :string, enum: %w[active archived] }
      parameter name: :page, in: :query, required: false, schema: { type: :integer }
      parameter name: :per_page, in: :query, required: false, schema: { type: :integer }

      response '200', 'projects listed' do
        schema '$ref' => '#/components/schemas/ProjectCollection'

        let(:status) { 'active' }

        run_test!
      end

      response '422', 'unknown status' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:status) { 'maybe' }

        run_test!
      end
    end

    post 'Create a project' do
      tags 'Projects'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/ProjectRequest' }

      response '201', 'project created' do
        schema '$ref' => '#/components/schemas/ProjectDetail'

        let(:body) { { project: { name: 'Kitchen', kind: 'project', budget: '5000' } } }

        run_test!
      end

      response '422', 'validation error' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:body) { { project: { name: '' } } }

        run_test!
      end
    end
  end

  path '/api/v1/projects/{id}' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Project ID'

    get 'Retrieve a project with its totals' do
      tags 'Projects'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'

      response '200', 'project retrieved' do
        schema '$ref' => '#/components/schemas/ProjectDetail'

        let(:id) { trip.id }

        before { trip.assign_transactions!([ hotel.entryable_id ]) }

        run_test!
      end

      response '404', 'project not found' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { SecureRandom.uuid }

        run_test!
      end
    end

    patch 'Update a project' do
      tags 'Projects'
      description 'Set archived to true to archive it, false to restore it.'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/ProjectRequest' }

      response '200', 'project updated' do
        schema '$ref' => '#/components/schemas/ProjectDetail'

        let(:id) { trip.id }
        let(:body) { { project: { budget: '2500' } } }

        run_test!
      end
    end

    delete 'Delete a project' do
      tags 'Projects'
      security [ { apiKeyAuth: [] } ]

      response '204', 'project deleted; its transactions and IOUs stay' do
        let(:id) { trip.id }

        run_test!
      end
    end
  end

  path '/api/v1/projects/{id}/transactions' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Project ID'

    post 'Add transactions to a project' do
      tags 'Projects'
      description 'A transaction belongs to at most one project, so this moves it from any other. ' \
                  "Only transactions in accounts you may annotate are added; the rest come back in ignored_ids."
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/ProjectTransactionsRequest' }

      response '200', 'transactions added' do
        schema '$ref' => '#/components/schemas/ProjectTransactionsResult'

        let(:id) { trip.id }
        let(:body) { { transaction_ids: [ hotel.entryable_id ] } }

        run_test!
      end

      response '422', 'no ids given' do
        schema '$ref' => '#/components/schemas/ErrorResponse'

        let(:id) { trip.id }
        let(:body) { { transaction_ids: [] } }

        run_test!
      end
    end

    delete 'Take transactions out of a project' do
      tags 'Projects'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: { '$ref' => '#/components/schemas/ProjectTransactionsRequest' }

      response '200', 'transactions removed' do
        schema '$ref' => '#/components/schemas/ProjectTransactionsResult'

        let(:id) { trip.id }
        let(:body) { { transaction_ids: [ hotel.entryable_id ] } }

        before { trip.assign_transactions!([ hotel.entryable_id ]) }

        run_test!
      end
    end
  end
end
