# frozen_string_literal: true

# @lat: [[scores-and-agreement#Scores and agreement#The one-time repair walks every term, not only the current one]]
namespace :sway do
  namespace :scores do
    desc "Recompute all derived scores from source (BillScore/BSD/LDS/LLS/ULTS)"
    task recompute_all: :environment do
      Bill.find_each { |bill| ScoreRecomputeService.recompute_bill!(bill) }

      terms = 0
      Legislator.find_each do |legislator|
        reader_links = UserLegislator.where(legislator_id: legislator.id).to_a

        legislator.legislator_terms.each do |legislator_term|
          ScoreRecomputeService.recompute_legislator!(legislator_term)
          reader_links.each do |reader_link|
            ScoreRecomputeService.recompute_user_legislator!(reader_link, legislator_term)
          end
          terms += 1
        end
      end

      puts "Recomputed scores for all bills and #{terms} terms of office, " \
           "including terms that have ended and members who have left."
    end
  end
end
