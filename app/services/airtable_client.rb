# frozen_string_literal: true

require "net/http"

# The smallest Airtable REST client the app needs: one upsert into one table
# of the program base. Merges on a text field, so a retry after a lost
# response cannot make a second row. The token is airtable.program_token in
# the Rails credentials. See wiki/concepts/where-data-lives.md.
class AirtableClient
  class Error < StandardError; end

  API  = "https://api.airtable.com/v0"
  BASE = "app6bsNzSTjbDHUQ9" # YSWS - cyberdeck

  def initialize(token: Rails.application.credentials.dig(:airtable, :program_token), base: BASE)
    raise Error, "airtable.program_token is not set" if token.blank?

    @token = token
    @base  = base
  end

  # Upserts one record. Returns the Airtable record id.
  def upsert(table, fields, merge_on:)
    uri = URI("#{API}/#{@base}/#{ERB::Util.url_encode(table)}")
    request = Net::HTTP::Patch.new(uri, "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json")
    request.body = { performUpsert: { fieldsToMergeOn: merge_on }, records: [ { fields: fields } ], typecast: true }.to_json

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) { |http| http.request(request) }
    raise Error, "Airtable #{response.code} on #{table}: #{response.body.to_s.first(300)}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("records").first.fetch("id")
  end
end
