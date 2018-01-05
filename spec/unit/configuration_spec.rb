# frozen_string_literal: true

require 'spec_helper'

describe Que do
  it ".use_prepared_statements should be the opposite of disable_prepared_statements" do
    original_verbose = $VERBOSE
    $VERBOSE = nil

    Que.use_prepared_statements.should == true
    Que.disable_prepared_statements.should == false

    Que.disable_prepared_statements = true
    Que.use_prepared_statements.should == false
    Que.disable_prepared_statements.should == true

    Que.disable_prepared_statements = nil
    Que.use_prepared_statements.should == true
    Que.disable_prepared_statements.should == false

    Que.use_prepared_statements = false
    Que.use_prepared_statements.should == false
    Que.disable_prepared_statements.should == true

    Que.use_prepared_statements = true
    Que.use_prepared_statements.should == true
    Que.disable_prepared_statements.should == false

    $VERBOSE = original_verbose
  end
end
