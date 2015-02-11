require 'rate-limit'
require_relative 'spec_helper'


describe RateLimit do
  include RedisHelper

  RateLimit.configure do |config|
    config.redis = RedisHelper.redis
  end

  let(:period) { 60 * 60 }
  let(:rate_limit) do
    RateLimit::Target.new(:test, "user1", max: 3, period: 60 * 60)
  end

  describe :increment do
    it "should be true when rate limit is not exceeded" do
      assert rate_limit.increment(1)
    end

    it "should be false when raise limit is exceeded" do
      assert rate_limit.increment(1)
      assert rate_limit.increment(2)
      assert !rate_limit.increment(1)
    end

    it "should raise an argument error if given a float" do
      assert_raises(ArgumentError) do
        rate_limit.increment(1.5)
      end
    end

    it "should be a no-op when limit would be exceeded" do
      rate_limit.increment(2)
      assert !rate_limit.increment(2)
      assert rate_limit.increment(1)
    end

    it "should be true when sufficient time passes" do
      assert rate_limit.increment(3)
      Timecop.travel(period / 2)
      assert rate_limit.increment(1)
      Timecop.travel(period)
      assert rate_limit.increment(3)
    end

    it "should only call eval once" do
      eval_spy = Spy.on(RedisHelper.redis, :eval).and_call_through
      rate_limit.increment(1)
      rate_limit.increment(1)
      rate_limit.increment(1)
      assert_equal 1, eval_spy.calls.count
    end
  end

  describe :increment! do
    it "should not raise error when rate limit is not exceeded" do
      rate_limit.increment!(1)
    end

    it "should raise error when rate limit is exceeded" do
      rate_limit.increment!(3)
      assert_raises(RateLimit::ExceededError) do
        rate_limit.increment!(1)
      end
    end
  end

  describe :exceeded? do
    it "should be true when amount would exceed limit" do
      rate_limit.increment(2)
      assert rate_limit.exceeded?(2)
    end

    it "should be false when amount would not exceed limit" do
      rate_limit.increment(2)
      assert !rate_limit.exceeded?(1)
    end
  end

  describe :used do
    it "should be 0 when there has been no incrementing" do
      assert_equal 0, rate_limit.used
    end

    it "should be the amount used" do
      rate_limit.increment(1)
      assert_equal 1, rate_limit.used
    end

    it "should decrease over time" do
      rate_limit.increment(2)
      Timecop.travel(period / 2)
      assert_equal 1, rate_limit.used
    end
  end

  describe :reset do
    it "should reset current count to 0" do
      rate_limit.increment(3)
      assert_equal 3, rate_limit.used
      rate_limit.reset
      assert_equal 0, rate_limit.used
    end
  end

  describe :decrement do
    it "should reduce the amount used" do
      rate_limit.increment(3)
      rate_limit.decrement(2)
      assert_equal 1, rate_limit.used
    end

    it "should not lower amount used below 0" do
      rate_limit.decrement(2)
      assert !rate_limit.increment(4)
      assert_equal 0, rate_limit.used
    end
  end
end
