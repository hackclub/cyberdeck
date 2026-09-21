# frozen_string_literal: true

require "test_helper"

# One RSVP row becomes one upsert into the RSVP table of the program base.
class SyncRsvpJobTest < ActiveJob::TestCase
  # A stand-in for AirtableClient that records the call instead of making it.
  class FakeClient
    attr_reader :calls

    def initialize(record_id: "recFAKE123", fail_with: nil)
      @record_id = record_id
      @fail_with = fail_with
      @calls = []
    end

    def upsert(table, fields, merge_on:)
      @calls << [ table, fields, merge_on ]
      raise AirtableClient::Error, @fail_with if @fail_with

      @record_id
    end
  end

  setup { @default_factory = SyncRsvpJob.client_factory }
  teardown { SyncRsvpJob.client_factory = @default_factory }

  def with_client(client)
    SyncRsvpJob.client_factory = -> { client }
    yield
  end

  test "creating an RSVP enqueues the job" do
    assert_enqueued_with(job: SyncRsvpJob) { Rsvp.create!(email: "ada@example.com") }
  end

  test "the job upserts on Email and stamps the row" do
    rsvp = Rsvp.create!(email: "ada@example.com", ip: "203.0.113.9", country: "AU", utm_source: "slack")
    client = FakeClient.new
    with_client(client) { SyncRsvpJob.perform_now(rsvp.id) }

    expected = { "Email" => "ada@example.com", "IP" => "203.0.113.9", "Country" => "AU", "utm_source" => "slack" }
    assert_equal [ [ "RSVP", expected, [ "Email" ] ] ], client.calls
    rsvp.reload
    assert_equal "recFAKE123", rsvp.airtable_record_id
    assert rsvp.synced?
  end

  test "a synced row is not sent again" do
    rsvp = Rsvp.create!(email: "ada@example.com")
    rsvp.update!(airtable_record_id: "recDONE", synced_at: Time.current)
    client = FakeClient.new
    with_client(client) { SyncRsvpJob.perform_now(rsvp.id) }
    assert_empty client.calls
  end

  test "an Airtable error retries and leaves the row unsynced" do
    rsvp = Rsvp.create!(email: "ada@example.com")
    client = FakeClient.new(fail_with: "Airtable 429 on RSVP")
    assert_enqueued_with(job: SyncRsvpJob) do
      with_client(client) { SyncRsvpJob.perform_now(rsvp.id) }
    end
    assert_not rsvp.reload.synced?
  end
end
