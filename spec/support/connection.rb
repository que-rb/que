shared_examples "a database connection" do
  it "should be able to execute SQL" do
    array = Que.execute("SELECT 1 AS one")
    array.should be_an_instance_of Array
    array.length.should == 1
    
    hash = array.first
    hash.keys.map(&:to_s).should == %w(one)
    hash.values.map(&:to_s).should == %w(1)
  end

  it "should be able to drop and create the jobs table" do
    DB.table_exists?(:que_jobs).should be true
    Que.drop!
    DB.table_exists?(:que_jobs).should be false
    Que.create!
    DB.table_exists?(:que_jobs).should be true
  end

  it "should be able to clear the jobs table" do
    DB[:que_jobs].insert :type => "Que::Job"
    DB[:que_jobs].count.should be 1
    Que.clear!
    DB[:que_jobs].count.should be 0
  end
end
