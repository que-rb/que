## Logging

By default, Que logs important information in JSON to either Rails' logger (when running in a Rails web process) or STDOUT (when running as a rake task). So, your logs will look something like:

    I, [2014-01-12T05:07:31.094201 #4687]  INFO -- : {"lib":"que","thread":104928,"event":"job_worked","elapsed":0.01045,"job":{"priority":"1","run_at":"2014-01-12 05:07:31.081877+00","job_id":"4","job_class":"MyJob","args":[],"error_count":"0"}}

Of course you can have it log wherever you like:

    Que.logger = Logger.new(...)

You can use Que's logger in your jobs anywhere you like:

    class MyJob
      def run
        Que.log my_output: "my string"
      end
    end

    #=> I, [2014-01-12T05:13:11.006776 #4914]  INFO -- : {"lib":"que","thread":24960,"my_output":"my string"}

Que will always add a 'lib' key, so you can easily filter its output from that of other sources, and the object_id of the thread that emitted the log, so you can follow the actions of a particular worker if you wish. You can also pass a :level key to set the level of the output:

    Que.log level: :debug, my_output: 'my string'
    #=> D, [2014-01-12T05:16:15.221941 #5088] DEBUG -- : {"lib":"que","thread":24960,"my_output":"my string"}

If you don't like JSON, you can also customize the format of the logging output by passing a callable object (such as a proc) to Que.log_formatter=. The proc should take a hash (the keys are symbols) and return a string. The keys and values are just as you would expect from the JSON output:

    Que.log_formatter = proc do |data|
      "Thread number #{data[:thread]} experienced a #{data[:event]}"
    end

If the log formatter returns nil or false, a nothing will be logged at all. You could use this to narrow down what you want to emit, for example:

    Que.log_formatter = proc do |data|
      if ['job_worked', 'job_unavailable'].include?(data[:event])
        JSON.dump(data)
      end
    end
