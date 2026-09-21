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

  # Every record in a table, following pagination. Returns the raw rows.
  def list(table)
    rows = []
    offset = nil
    loop do
      uri = URI("#{API}/#{@base}/#{ERB::Util.url_encode(table)}")
      uri.query = URI.encode_www_form({ pageSize: 100, offset: offset }.compact)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
        http.request(Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{@token}"))
      end
      raise Error, "Airtable #{response.code} on #{table}: #{response.body.to_s.first(300)}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      rows.concat(body.fetch("records", []))
      offset = body["offset"]
      break if offset.blank?
    end
    rows
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
