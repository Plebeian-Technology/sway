xml.instruct! :xml, version: "1.0"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
    xml.url { xml.loc root_url }

    xml.url { xml.loc sway_locales_url }

    xml.url { xml.loc bills_url }

    xml.url { xml.loc legislators_url }

    @sway_locales.each { |object| xml.url { xml.loc bill_of_the_week_index_url(sway_locale_id: object.id) } }

    @bills.each do |object|
        xml.url do
            xml.loc bill_url(object, sway_locale_id: object.sway_locale.id) # Replace object_url with your URL helper
        end
    end

    @legislators.each do |object|
        xml.url do
            xml.loc legislator_url(object, sway_locale_id: object.sway_locale.id) # Replace object_url with your URL helper
        end
    end
end
