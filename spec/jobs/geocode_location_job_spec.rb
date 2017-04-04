require 'rails_helper'

describe GeocodeLocationJob do
  include ActiveJob::TestHelper

  describe '#perform' do
    before do
      # Stub Geocoder.search so that tests don't use precious API
      allow(Geocoder).to receive(:search)
    end

    it 'moves on to geocode the next location when geocodable? is false' do
      results = [double(
        city: 'Berlin',
        country: 'Germany',
        coordinates: [52.5200066, 13.404954]
      )]
      allow(Geocoder).to receive(:search).and_return(results)

      org = Fabricate :organization
      org.locations.create(
        content: 'New York City', latitude: 1234, longitude: 5678
      )
      org.locations.create content: '401 Broadway, New York City'
      import = Fabricate :import

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id
        assert_performed_jobs 2
      end

      expect(org.locations.last.latitude).to eql results.first.coordinates[0]
      expect(org.locations.last.longitude).to eql results.first.coordinates[1]
      expect(org.locations.last.country).to eql results.first.country
      expect(org.locations.last.city).to eql results.first.city
    end

    it 'stops raises an error when OverQueryLimitError is raised' do
      expect(Geocoder).to receive(:search)
        .and_raise(Geocoder::OverQueryLimitError)
      org = Fabricate :organization
      org.locations.create(
        content: 'New York City', latitude: 1234, longitude: nil
      )
      import = Fabricate :import

      perform_enqueued_jobs do
        expect do
          GeocodeLocationJob.perform_later import.id
        end.to raise_error Geocoder::OverQueryLimitError
      end
    end

    it 'enqueues one job after another, after another, after another...' do
      org = Fabricate :organization
      org.locations.create content: 'Berlin, Germany'
      org.locations.create content: '401 Broadway, New York City'
      import = Fabricate :import

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id
        assert_performed_jobs 3
      end
    end

    it 'gracefully exits when no more next_location exist' do
      org = Fabricate :organization
      org.locations.create content: 'Berlin, Germany'
      org.locations.create(
        content: 'New York City', latitude: 1234, longitude: 5678
      )
      import = Fabricate :import

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id
        assert_performed_jobs 2
      end
    end

    it 'only does jobs for non-geocoded Locations' do
      org = Fabricate :organization
      org.locations.create content: 'Berlin, Germany'
      org.locations.create(
        content: 'New York City', latitude: 1234, longitude: 5678
      )
      import = Fabricate :import

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id
        assert_performed_jobs 2
        assert_enqueued_jobs 0
      end
    end

    it 'saves location with fallback value when Geocoder results are nil' do
      fallback_coordinates = GeocodeLocationJob::FALLBACK_COORDINATES

      allow(Geocoder).to receive(:search)
        .and_return(nil)

      org = Fabricate :organization
      org.locations.create content: 'Nil Town, USA'
      import = Fabricate :import

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id
      end

      expect(org.locations.first.latitude).to eql fallback_coordinates[0]
      expect(org.locations.first.longitude).to eql fallback_coordinates[1]
      expect(org.locations.first.country).to eql nil
      expect(org.locations.first.city).to eql nil
    end

    it 'records an Import and Source for all records' do
      organization = Fabricate :organization
      Fabricate :location, latitude: nil, organization: organization
      Fabricate :location, latitude: nil, organization: organization

      source = Fabricate :source, name: 'Foo Geocoding, Inc.'
      description = 'Testing, testing'
      import = Fabricate :import, source: source, description: description

      perform_enqueued_jobs do
        GeocodeLocationJob.perform_later import.id

        assert_performed_jobs 3
        expect(Source.count).to eql 1
        expect(Location.count).to eql 2

        Location.all.each do |location|
          actor = location.versions.last.actor
          expect(actor).to eq import
          expect(actor.description).to eq description
          expect(actor.source).to eq source
        end
      end
    end
  end
end
