require 'json'

module Que
  class Job
    class << self
      def queue(*args)
        Que.execute "INSERT INTO que_jobs (type, args) VALUES ($1, $2);", [to_s, JSON.dump(args)]
      end
    end
  end
end
