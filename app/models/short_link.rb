# frozen_string_literal: true

# A short link. `cyberdeck.hackclub.com/k3` carries the same meaning as a
# long query string of utm parameters, without showing any of it.
#
# The codes live in the "Short Links" table of the program base, so Armand
# edits them himself with no deploy. The app reads the whole table at most
# once a minute and holds it in the cache. When Airtable is unreachable the
# last good copy is used, so a link never stops working mid-campaign.
# See wiki/decisions/D-027-short-links.md.
class ShortLink
  TABLE  = "Short Links"
  TTL    = 1.minute
  CACHE  = "short_links"
  FORMAT = /\A[a-z0-9-]{2,24}\z/
  # The same shape without anchors. A route constraint refuses them, and
  # Rails anchors a segment itself.
  ROUTE  = /[a-z0-9-]{2,24}/
  # The Airtable column for each utm value.
  FIELDS = { "Source" => "utm_source", "Medium" => "utm_medium",
             "Campaign" => "utm_campaign", "Content" => "utm_content" }.freeze

  class << self
    # The utm values for a code, or nil when there is no such link.
    def utm_for(code)
      code = code.to_s.strip.downcase
      return nil unless code.match?(FORMAT)

      all[code]
    end

    def all
      Rails.cache.fetch(CACHE, expires_in: TTL) { fetch }
    rescue StandardError => e
      Rails.logger.warn("[ShortLink] falling back to the last good copy: #{e.message}")
      @last_good || {}
    end

    private

    def fetch
      map = AirtableClient.new.list(TABLE).each_with_object({}) do |record, acc|
        fields = record["fields"] || {}
        code = fields["Code"].to_s.strip.downcase
        next unless code.match?(FORMAT)

        utm = FIELDS.filter_map do |column, key|
          value = fields[column].to_s.strip.first(200)
          [ key, value ] if value.present?
        end.to_h
        acc[code] = utm if utm.any?
      end
      @last_good = map
    end
  end
end
