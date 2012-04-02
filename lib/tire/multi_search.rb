module Tire
  class MultiSearch
    include Enumerable
    attr_accessor :searches, :results, :options, :response, :json
    def initialize(searches=[], specified_options={})
      default_options = {}
      @options = default_options.merge(specified_options)
      @searches = []
    end
    def add(o)
      @searches << o if o.instance_of?(Tire::Search::Search) && !include?(o)
    end
    def each &block
      @searches.each{|search| block.call(search)}
    end
    def results
      @results  || (perform; @results)
    end
    def perform
      @response = multi_search
      if @response.failure?
        STDERR.puts "[REQUEST FAILED] #{self.to_curl}\n"
        raise SearchRequestFailed, @response.to_s
      end
      @json = MultiJson.decode(@response.body)
      @results = @json['responses'].map do |response|
        if response.has_key? "error"
          []
        else
          Tire::Results::Collection.new(response)
        end
      end
      return self
    ensure
      logged
    end
    def url
      Configuration.url + "/_msearch"
    end
    def to_json
      payload = map do |search|
        output = []
        output << %Q|{"index": "#{search.indices.first}"}|
        output << search.to_hash.to_json
        output.join("\n")
      end
      payload << ""
      payload.join("\n")
    end
    def multi_search
      tries = 5
      count = 0
      begin
        response = Configuration.client.get(url, to_json)
        raise RuntimeError, "#{response.code} > #{response.body}" if response.failure?
        response
      rescue StandardError => error
        if count < tries
          count += 1
          STDERR.puts "[ERROR] #{error.message}, retrying (#{count})..."
          retry
        else
          STDERR.puts "[ERROR] Too many exceptions occured, giving up. The HTTP response was: #{error.message}"
          raise if options[:raise]
        end
      ensure
        curl = %Q|curl -X POST "#{url}" -d '{... data omitted ...}'|
        logged
      end
    end
    def indices
      map {|search| search.indices}
    end
    def params
      @options.empty? ? '' : '?' + @options.to_param
    end
    def to_curl
        %Q|curl -X POST "#{url}#{params.empty? ? '?' : params.to_s + '&'}pretty=true" -d '#{to_json}'|
    end
    def logged
      if Configuration.logger

        Configuration.logger.log_request '_msearch', indices, to_curl

        took = @json['took']  rescue nil
        code = @response.code rescue nil

        if Configuration.logger.level.to_s == 'debug'
          # FIXME: Depends on RestClient implementation
          body = if @json
            defined?(Yajl) ? Yajl::Encoder.encode(@json, :pretty => true) : MultiJson.encode(@json)
          else
            @response.body rescue nil
          end
        else
          body = ''
        end

        Configuration.logger.log_response code || 'N/A', took || 'N/A', body || 'N/A'
      end
    end
  end
end
