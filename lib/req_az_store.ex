defmodule ReqAzStore do
  require Logger

  # headers that must be included in the signature string
  @signature_string_headers [
    "content-encoding",
    "content-language",
    "content-length",
    "content-md5",
    "content-type",
    "date",
    "if-modified-since",
    "if-match",
    "if-none-match",
    "if-unmodified-since",
    "range"
  ]

  # these options are registered for use on the request.
  @registered_options [
    :ms_date,
    :ms_version,
    :account_name,
    :account_key
  ]

  @doc """
  Appends needed request steps for Azure storage authorization to the request.

  ## Options
  The following options are added to the request.
    * :account_name - **Mandatory** the name of your azure storage account.
    * :account_key - **Mandatory** the key for your account.  This key is used to sign requests.
    * :ms_date - if set, sets the date of the request.  Must be in RFC2616 format. Defaults to utc_now.
    * :ms_version - api version to use, defaults to 2023-11-03.
  """

  @spec attach(Req.Request.t()) :: Req.Request.t()
  def attach(request) do
    request
    |> Req.Request.register_options(@registered_options)
    |> Req.Request.append_request_steps(req_azurestorage_ms_date: &add_ms_date_header/1)
    |> Req.Request.append_request_steps(req_azurestorage_ms_version: &add_ms_version/1)
    |> Req.Request.append_request_steps(req_azurestorage_sign: &add_auth_signature/1)
  end

  @doc """
  Adds an x-ms-version header to the request, will default to 2023-11-03 if
  no option value has been set.
  """
  @spec add_ms_version(Req.Requst.t()) :: Req.Request.t()
  def add_ms_version(request) do
    version = Req.Request.get_option(request, :ms_version, "2023-11-03")

    request
    |> Req.Request.put_header("x-ms-version", version)
  end

  @doc """
  Adds the option value for ms_date as x-ms-date header, defautls to datetime
  for utc now if no option value is provided.
  """
  @spec add_ms_date_header(Req.Request.t()) :: Req.Request.t()
  def add_ms_date_header(request) do
    date = Req.Request.get_option(request, :ms_date, rfc2616_datetime_now())

    request
    |> Req.Request.put_header("x-ms-date", date)
  end

  @doc """
  Creates the auth signature header as described in MSFT documentation.
  [MSFT Docs Page](https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key)
  """
  @spec add_auth_signature(Req.Request.t()) :: Req.Request.t()
  def add_auth_signature(request) do
    with {:ok, account_key} <- get_account_key(request),
         {:ok, _account_name} <- get_account_name(request) do
      sig_string = create_signature_string(request)
      signing_key = Base.decode64!(account_key)

      signature =
        :crypto.mac(:hmac, :sha256, signing_key, sig_string)
        |> Base.encode64()

      request
      |> add_authorization_header(signature)
    else
      {:error, "account_key not set"} -> raise ArgumentError, "account_key option must be set!"
      {:error, "account_name not set"} -> raise ArgumentError, "account_name option must be set!"
    end
  end

  @doc """
  Creates signature string as described in the MSFT docs (see page linked in add_auth_signature/1).
  """
  @spec create_signature_string(Req.Request.t()) :: String.t()
  def create_signature_string(request) do
    request
    |> add_verb_line()
    |> add_header_lines(request)
    |> add_canonicalized_headers(request)
    |> add_canonicalized_resource(request)
  end

  @spec get_account_key(Req.Request.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp get_account_key(request) do
    case Req.Request.fetch_option(request, :account_key) do
      :error -> {:error, "account_key not set"}
      ok_tuple -> ok_tuple
    end
  end

  @spec get_account_name(Req.Request.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp get_account_name(request) do
    case Req.Request.fetch_option(request, :account_name) do
      :error -> {:error, "account_name not set"}
      ok_tuple -> ok_tuple
    end
  end

  @spec add_verb_line(Req.Request.t()) :: String.t()
  defp add_verb_line(request) do
    "#{method_to_string(request)}\n"
  end

  @spec add_canonicalized_headers(String.t(), Req.Request.t()) :: String.t()
  defp add_canonicalized_headers(initial_string, request) do
    canonicalized_headers =
      request
      |> extract_ms_headers()
      |> Enum.sort_by(fn {k, _v} -> k end, :asc)
      |> Enum.map(fn {k, v} -> {k, Regex.replace(~r/\s+/, v, " ")} end)
      |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
      |> Enum.join("\n")

    initial_string <> canonicalized_headers <> "\n"
  end

  @spec add_canonicalized_resource(String.t(), Req.Request.t()) :: String.t()
  defp add_canonicalized_resource(inital_string, request) do
    starting_canon =
      Path.join(["/", Req.Request.fetch_option!(request, :account_name), request.url.path])

    canon_parameters = canon_parameters(Req.Request.get_option(request, :params, []))

    canon_resource = "#{starting_canon}#{canon_parameters}"

    Logger.info(cannon_resource: canon_resource)

    "#{inital_string}#{canon_resource}"
  end

  @spec add_header_lines(String.t(), Req.Request.t()) :: String.t()
  defp add_header_lines(initial_string, request) do
    headers = extract_headers(request)

    Enum.reduce(@signature_string_headers, initial_string, fn header, string ->
      string <> "#{get_header_value(headers, header)}\n"
    end)
  end

  @spec add_authorization_header(Req.Request.t(), String.t()) :: Req.Request.t()
  defp add_authorization_header(request, signature) do
    Req.Request.put_header(
      request,
      "Authorization",
      auhtorization_header(Req.Request.get_option(request, :account_name), signature)
    )
  end

  @spec auhtorization_header(String.t(), String.t()) :: String.t()
  defp auhtorization_header(account_name, signature) do
    "SharedKey #{account_name}:#{signature}"
  end

  @spec get_header_value(%{} | %{String.t() => String.t() | number()}, String.t()) ::
          String.t() | number()
  defp get_header_value(headers, "content-length") do
    case Map.get(headers, "content-length") do
      nil ->
        ""

      "0" ->
        ""

      value ->
        value
    end
  end

  defp get_header_value(headers, header) do
    Map.get(headers, header, "")
  end

  @spec canon_parameters([] | keyword(String.t() | number())) :: String.t()
  defp canon_parameters([]) do
    ""
  end

  defp canon_parameters(params) do
    Logger.info(received_params: params)

    params
    |> Enum.sort_by(fn {k, _v} -> to_string(k) end, :asc)
    |> Enum.map(fn {k, v} -> "\n#{to_string(k)}:#{to_string(v)}" end)
    |> Enum.join("")
  end

  @spec method_to_string(Req.Request.t()) :: String.t()
  defp method_to_string(request) do
    request.method
    |> Atom.to_string()
    |> String.upcase()
  end

  @spec extract_headers(Req.Request.t()) :: %{String.t() => String.t() | number()}
  defp extract_headers(request) do
    request.headers
    |> Enum.map(fn {k, [v]} -> {k, v} end)
    |> Map.new()
  end

  @spec extract_headers(Req.Request.t()) :: %{String.t() => String.t() | number()}
  defp extract_ms_headers(request) do
    request
    |> extract_headers()
    |> Enum.filter(fn {k, _v} ->
      Regex.match?(~r/^x-ms-.*/, k)
    end)
  end

  @spec rfc2616_datetime_now() :: String.t()
  defp rfc2616_datetime_now() do
    Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %X GMT")
  end
end
