defmodule ReqAzStoreTest do
  use ExUnit.Case

  test "creates correct signature string" do
    # simple echo plug to run tests against
    echo = fn conn ->
      "/" <> path = conn.request_path
      Plug.Conn.send_resp(conn, 200, path)
    end

    # the settings used here are taken directly from MSFT docs
    # should model a get blob operation
    date_string = "Fri, 26 Jun 2015 23:39:12 GMT"
    version = "2015-02-21"
    account_name = "myaccount"
    container = "mycontainer"
    timeout = 20
    restype = "container"
    # the key value does not matter for this test, setting random value
    account_key = Stream.repeatedly(fn -> Enum.random(1..9) end) |> Enum.take(64) |> Enum.join("")

    req =
      Req.new(url: "https://#{account_name}.blob.core.windows.net/#{container}")
      |> ReqAzStore.attach()
      |> Req.Request.merge_options(
        account_name: account_name,
        account_key: account_key,
        ms_version: version,
        ms_date: date_string,
        params: [comp: "metadata", restype: "container", timeout: 20],
        plug: echo,
        method: :get
      )

    {request, _response} = Req.Request.run_request(req)

    assert "GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:Fri, 26 Jun 2015 23:39:12 GMT\nx-ms-version:2015-02-21\n/myaccount/mycontainer\ncomp:metadata\nrestype:container\ntimeout:20" ==
             ReqAzStore.create_signature_string(request)
  end
end
