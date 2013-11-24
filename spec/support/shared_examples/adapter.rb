shared_examples "a Que adapter" do
  it "should allow a Postgres connection to be checked out" do
    Que.adapter.checkout do |conn|
      conn.execute("SELECT 1 AS one").to_a.should == [{'one' => '1'}]
    end
  end

  it "should allow nested checkouts" do
    Que.adapter.checkout do |a|
      Que.adapter.checkout do |b|
        a.object_id.should == b.object_id
      end
    end
  end
end
