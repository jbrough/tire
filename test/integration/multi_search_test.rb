module Tire

  class MultiSearchIntegrationTest < Test::Unit::TestCase
    include Test::Integration

    context "Query results" do

      should "allow easy access to returned documents" do
        q = 'title:one'
        s = Tire::MultiSearch.new
        s.add Tire.search('articles-test') { query { string q } }
        assert_equal 'One',  s.results.first.first.title
        assert_equal 'ruby', s.results.first.first.tags[0]
      end

    end

  end

end
