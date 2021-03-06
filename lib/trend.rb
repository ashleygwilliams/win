require 'redis/set'

class Trend < Model

  def self.add_mention(keyword, trendset, timestamp)
    trend_set = Redis::Set.new("trends:#{trendset}:keys", redis)
    trend_set << keyword

    set = Redis::Set.new("trends:#{trendset}:#{keyword}:timestamps", redis)
    timestamp = Time.parse(timestamp).to_i
    set << timestamp
  end

  def self.get_trend(trendset, keyword)
    timestamps = Redis::Set.new("trends:#{trendset}:#{keyword}:timestamps", redis)
    timestamps = timestamps.members
    timestamps.map! {|time_str| Time.at(time_str.to_i) }

    {
      :name => keyword,
      :total_mentions => timestamps.count,
      :mentions => timestamps
    }
  end

  def self.all(trendset = '*')
    trends = []

    trend_set = redis.keys "trends:#{trendset}:*:timestamps"
    trend_set.each do |member|
      keyword = member.split(':')[2]
      trends << get_trend(trendset, keyword)
    end

    trends.sort! {|a, b| b[:total_mentions] <=> a[:total_mentions] }

    trends
  end

  def self.score_for_post(post, trendset)
    points = 0
    post[:keywords].each do |keyword|
      trend = get_trend(trendset, keyword)
      points += calculate_timeliness(post, trend)
    end
    points * post[:amps]
  end

  def self.calculate_timeliness(post, trend)
    trend_count = trend[:total_mentions]
    mentions = trend[:mentions].sort {|a,b| a <=> b }

    points = 0
    post_index = 0
    mentions.each do |mention|
      post_index += 1 if mention < post[:timestamp]
    end

    if post_index == 0
      points += 10
    else
      quotient = (post_index.to_f / trend_count.to_f)
      case 
      when quotient <= 0.1
        points += 7.5
      when quotient > 0.1 && quotient <= 0.25
        points += 5
      when quotient > 0.25 && quotient <= 0.5
        points += 2.5
      when quotient > 0.5
        points += 1
      end
    end
    points * trend_count
  end
end
