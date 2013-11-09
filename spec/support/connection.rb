shared_examples "a database connection" do
  it "should be able to execute SQL" do
    array = Que.execute("SELECT 1 AS one")
    array.should be_an_instance_of Array
    array.length.should == 1
    
    hash = array.first
    hash.keys.map(&:to_s).should == %w(one)
    hash.values.map(&:to_s).should == %w(1)
  end
end
