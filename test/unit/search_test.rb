require 'test_helper'

module Tire

  class SearchTest < Test::Unit::TestCase

    context "Search" do
      setup { Configuration.reset }

      should "be initialized with single index" do
        s = Search::Search.new('index') { query { string 'foo' } }
        assert_match %r|/index/_search|, s.url
      end

      should "be initialized with multiple indices" do
        s = Search::Search.new(['index1','index2']) { query { string 'foo' } }
        assert_match %r|/index1,index2/_search|, s.url
      end

      should "be initialized with multiple indices as string" do
        s = Search::Search.new(['index1,index2,index3']) { query { string 'foo' } }
        assert_match %r|/index1,index2,index3/_search|, s.url
      end

      should "allow to search all indices by leaving index empty" do
        s = Search::Search.new { query { string 'foo' } }
        assert_match %r|localhost:9200/_search|, s.url
      end

      should "allow to limit results with document type" do
        s = Search::Search.new('index', :type => 'bar') do
          query { string 'foo' }
        end

        assert_match %r|index/bar/_search|, s.url
      end

      should "allow to pass search parameters" do
        s = Search::Search.new('index', :routing => 123, :timeout => 1) { query { string 'foo' } }

        assert  ! s.params.empty?

        assert_match %r|routing=123|, s.params
        assert_match %r|timeout=1|,   s.params
      end

      should "encode search parameters in the request" do
        Configuration.client.expects(:get).with do |url, payload|
          url.include? 'routing=123&timeout=1'
        end.returns mock_response( { 'hits' => { 'hits' => [ {:_id => 1} ] } }.to_json )

        Search::Search.new('index', :routing => 123, :timeout => 1) { query { string 'foo' } }.perform
      end

      should "encode missing params as an empty string" do
        Configuration.client.expects(:get).with do |url, payload|
          (! url.include? '?') && (! url.include? '&')
        end.returns mock_response( { 'hits' => { 'hits' => [ {:_id => 1} ] } }.to_json )

        s = Search::Search.new('index') { query { string 'foo' } }
        s.perform

        assert_equal '', s.params
      end

      should "properly encode namespaced document type" do
        Configuration.client.expects(:get).with do |url, payload|
          url.match %r|index/my_application%2Farticle/_search|
        end.returns mock_response( { 'hits' => { 'hits' => [ {:_id => 1} ] } }.to_json )

        s = Search::Search.new('index', :type => 'my_application/article') do
          query { string 'foo' }
        end
        s.perform

        assert_match %r|index/my_application%2Farticle/_search|, s.url
        assert_match %r|index/my_application%2Farticle/_search|, s.to_curl
      end

      should "allow to pass block to query" do
        Search::Query.any_instance.expects(:instance_eval)

        Search::Search.new('index') do
          query { string 'foo' }
        end
      end

      should "allow to pass block with argument to query (use variables from outer scope)" do
        def foo; 'bar'; end

        Search::Query.any_instance.expects(:instance_eval).never

        Search::Search.new('index') do |search|
          search.query do |query|
            query.string foo
          end
        end
      end

      should "store indices as an array" do
        s = Search::Search.new('index1') do;end
        assert_equal ['index1'], s.indices

        s = Search::Search.new(['index1', 'index2']) do;end
        assert_equal ['index1', 'index2'], s.indices
      end

      should "return curl snippet for debugging" do
        s = Search::Search.new('index') do
          query { string 'title:foo' }
        end
        assert_equal %q|curl -X GET "http://localhost:9200/index/_search?pretty=true" -d | +
                     %q|'{"query":{"query_string":{"query":"title:foo"}}}'|,
                     s.to_curl
      end

      should "return curl snippet with multiple indices for debugging" do
        s = Search::Search.new(['index_1', 'index_2']) do
          query { string 'title:foo' }
        end
        assert_match /index_1,index_2/, s.to_curl
      end

      should "return itself as a Hash" do
        s = Search::Search.new('index') do
          query { string 'title:foo' }
        end
        assert_nothing_raised do
          assert_instance_of Hash,  s.to_hash
          assert_equal "title:foo", s.to_hash[:query][:query_string][:query]
        end
      end

      should "allow chaining" do
        assert_nothing_raised do
          Search::Search.new('index').query { }.
                                      sort { by :title, 'desc' }.
                                      size(5).
                                      sort { by :name, 'asc' }.
                                      from(1)
        end
      end

      should "perform the search lazily" do
        response = mock_response '{"took":1,"hits":[]}', 200
        Configuration.client.expects(:get).returns(response)
        Results::Collection.expects(:new).returns([])

        s = Search::Search.new('index')
        assert_not_nil s.results
        assert_not_nil s.response
      end

      should "allow the search criteria to be chained" do
        s = Search::Search.new('index').query { string 'foo' }
        assert_nil s.filters, "Should NOT have filters"

        s.expects(:perform).once
        s.filter :term, :other_field => 'bar'
        assert s.filters.size == 1, "Should have filters"
        s.results
      end

      should "print debugging information on exception and return false" do
        ::RestClient::Request.any_instance.
                              expects(:execute).
                              raises(::RestClient::InternalServerError)
        STDERR.expects(:puts)

        s = Search::Search.new('index')
        assert_raise Search::SearchRequestFailed do
          s.perform
        end
      end

      should "log request, but not response, when logger is set" do
        Configuration.logger STDERR

        Configuration.client.expects(:get).returns(mock_response( '{"took":1,"hits":[]}', 200 ))

        Results::Collection.expects(:new).returns([])
        Configuration.logger.expects(:log_request).returns(true)
        Configuration.logger.expects(:log_response).with(200, 1, '')

        Search::Search.new('index').perform
      end

      should "log the original exception on failed request" do
        Configuration.logger STDERR

        Configuration.client.expects(:get).raises(Errno::ECONNREFUSED)
        Configuration.logger.expects(:log_response).with('N/A', 'N/A', '')

        assert_raise Errno::ECONNREFUSED do
          Search::Search.new('index').perform
        end
      end

      should "allow to set the server url" do
        search = Search::Search.new('indexA')
        Configuration.url 'http://es1.example.com'

        Configuration.client.
          expects(:get).
            with do |url, payload|
              url == 'http://es1.example.com/indexA/_search'
            end.
          returns(mock_response( '{"took":1,"hits":{"total": 0, "hits" : []}}', 200 ))

        search.perform
      end

      context "sort" do

        should "allow sorting by multiple fields" do
          s = Search::Search.new('index') do
            sort do
              by :title, 'desc'
              by :_score
            end
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal [{'title' => 'desc'}, '_score'], hash['sort']
        end

      end

      context "facets" do

        should "retrieve terms facets" do
          s = Search::Search.new('index') do
            facet('foo1') { terms :bar, :global => true }
            facet('foo2', :global => true) { terms :bar }
            facet('foo3') { terms :baz }
          end
          assert_equal 3, s.facets.keys.size
          assert_not_nil s.facets['foo1']
          assert_not_nil s.facets['foo2']
          assert_not_nil s.facets['foo3']
        end

        should "retrieve date histogram facets" do
          s = Search::Search.new('index') do
            facet('date') { date :published_on }
          end
          assert_equal 1, s.facets.keys.size
          assert_not_nil  s.facets['date']
        end

      end

      context "filter" do

        should "allow to specify filter" do
          s = Search::Search.new('index') do
            filter :terms, :tags => ['foo']
          end

          assert_equal 1, s.filters.size

          assert_not_nil s.filters.first
          assert_not_nil s.filters.first[:terms]

          assert_equal( {:terms => {:tags => ['foo']}}.to_json,
                        s.to_hash[:filter].to_json )
        end

        should "allow to add multiple filters" do
          s = Search::Search.new('index') do
            filter :terms, :tags  => ['foo']
            filter :term,  :words => 125
          end

          assert_equal 2, s.filters.size

          assert_not_nil  s.filters.first[:terms]
          assert_not_nil  s.filters.last[:term]

          assert_equal( { :and => [ {:terms => {:tags => ['foo']}}, {:term => {:words => 125}} ] }.to_json,
                        s.to_hash[:filter].to_json )
        end

      end

      context "highlight" do

        should "allow to specify highlight for single field" do
          s = Search::Search.new('index') do
            highlight :body
          end

          assert_not_nil s.highlight
          assert_instance_of Tire::Search::Highlight, s.highlight
        end

        should "allow to specify highlight for more fields" do
          s = Search::Search.new('index') do
            highlight :body, :title
          end

          assert_not_nil s.highlight
          assert_instance_of Tire::Search::Highlight, s.highlight
        end

        should "allow to specify highlight with for more fields with options" do
          s = Search::Search.new('index') do
            highlight :body, :title => { :fragment_size => 150, :number_of_fragments => 3 }
          end

          assert_not_nil s.highlight
          assert_instance_of Tire::Search::Highlight, s.highlight
        end

      end

      context "with version" do

        should "set the version value in options" do
          s = Search::Search.new('index') do
            version true
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal true, hash['version']
        end

      end


      context "with from/size" do

        should "set the values in request" do
          s = Search::Search.new('index') do
            size 5
            from 3
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal 5, hash['size']
          assert_equal 3, hash['from']
        end

        should "set the size value in options" do
          Results::Collection.any_instance.stubs(:total).returns(50)
          s = Search::Search.new('index') do
            size 5
          end

          assert_equal 5, s.options[:size]
        end

        should "set the from value in options" do
          Results::Collection.any_instance.stubs(:total).returns(50)
          s = Search::Search.new('index') do
            from 5
          end

          assert_equal 5, s.options[:from]
        end

      end

      context "when limiting returned fields" do

        should "set the fields limit in request" do
          s = Search::Search.new('index') do
            fields :title
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal ['title'], hash['fields']
        end

        should "take multiple fields as an Array" do
          s = Search::Search.new('index') do
            fields [:title, :tags]
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal ['title', 'tags'], hash['fields']
        end

        should "take multiple fields as splat argument" do
          s = Search::Search.new('index') do
            fields :title, :tags
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal ['title', 'tags'], hash['fields']
        end

      end

      context "explain" do

        should "default to false" do
          s = Search::Search.new('index') do
          end
          hash = MultiJson.decode( s.to_json )
          assert_nil hash['explain']
        end

        should "set the explain field in the request when true" do
          s = Search::Search.new('index') do
            explain true
          end
          hash = MultiJson.decode( s.to_json )
          assert_equal true, hash['explain']
        end

        should "not set the explain field when false" do
          s = Search::Search.new('index') do
            explain false
          end
          hash = MultiJson.decode( s.to_json )
          assert_nil hash['explain']
        end

      end

      context "boolean queries" do

        should "wrap other queries" do
          # TODO: Try to get rid of the `boolean` method
          #
          # TODO: Try to get rid of multiple `should`, `must`, invocations, and wrap queries like this:
          #       boolean do
          #         should do
          #           string 'foo'
          #           string 'bar'
          #         end
          #       end
          s = Search::Search.new('index') do
            query do
              boolean do
                should { string 'foo' }
                should { string 'moo' }
                must   { string 'title:bar' }
                must   { terms  :tags, ['baz']  }
              end
            end
          end

          hash  = MultiJson.decode(s.to_json)
          query = hash['query']['bool']
          # p hash

          assert_equal 2, query['should'].size
          assert_equal 2, query['must'].size

          assert_equal( { 'query_string' => { 'query' => 'foo' } }, query['should'].first)
          assert_equal( { 'terms' => { 'tags' => ['baz'] } }, query['must'].last)
        end

      end

      context "groupField queries" do

        should "set not set the group_field value in request" do
          s = Search::Search.new('index')
          hash = MultiJson.decode( s.to_json )
          assert_nil hash['groupField']
        end

        should "set the group_field value in request" do
          s = Search::Search.new('index',  :group_field => 'foo')
          hash = MultiJson.decode( s.to_json )
          assert_equal 'foo', hash['groupField']
        end

        should "set the group_field value in options" do
          Results::Collection.any_instance.stubs(:total).returns(50)
          s = Search::Search.new('index', :group_field => 'foo')
          assert_equal 'foo', s.options[:group_field]
        end

      end

      context "sort by geo location" do
        should "build a request sorted by location" do
          s = Tire::Search::Search.new('index')
          s.sort { geo 'geohash' }
          body = JSON.parse(s.to_json)
          assert_equal true, body.has_key?('sort')
          assert_equal 1, body['sort'].size
          geo = body['sort'].first
          assert_equal true, geo.has_key?('_geo_distance')
          loc = geo['_geo_distance']
          assert_equal true, loc.has_key?('location')
          assert_equal true, loc.has_key?('order')
          assert_equal true, loc.has_key?('unit')
          assert_equal 'geohash', loc['location']
        end

      end

    end

  end

end
