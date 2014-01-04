In order to remain simple and compatible with any ORM (or no ORM at all), Que is really just a very thin wrapper around some raw SQL. If you want to query the jobs table yourself to see what's been queued or the state of various jobs, you can define your own ActiveRecord model around Que's job table:

    class QueJob < ActiveRecord::Base
    end

    # Or:

    class MyJob < ActiveRecord::Base
      self.table_name = :que_jobs
    end

Then you can query just as you would with any other model. If you're using Sequel, you can use the dataset methods you're already used to:

    DB[:que_jobs].all
