(** Module to provide OpenID identification *)

(** This module implements the Relying Party of the OpenID specification,
    in stateful mode. *)
(** {1 Library description} *)

(** The library provides means to authentificate an user
    to a remote provider using the OpenID protocol.
    Basically, you need to ask the user its OpenID url, and
    the fields you want to require (or none, if you just want to
    authentificate an user), along with other information.
    
    The library uses an "hidden service" that is needed when the provider
    redirects back to your site. This service is registered in the library, all you have
    to do is to give a path for that service and a default handler 
    (if the user connects to that service without being in an authentification process.)
    Here is a short example of how to use the library
    {[
open Eliom_openid
let messages = Eliom_sessions.create_volatile_table ()
(* The login form *)
let login_form = Eliom_services.new_service
  ~path:["login-form"]
  ~get_params: Eliom_parameters.unit
  ()

(* Initialize the library, and getting the authentificate function *)
let authentificate = Eliom_openid.init ~path:["__openid_return_service"]
    ~f: (fun sp _ _ -> Eliom_predefmod.Redirection.send ~sp login_form)

(* Create the handler for the form *)
(* We have to use Eliom_predefmod.String_redirection as we
   redirect the user to her provider *)
let form_handler = Eliom_predefmod.String_redirection.register_new_post_coservice
    ~fallback: login_form
    ~post_params: (Eliom_parameters.string "url")
    (fun sp _ url ->
       authentificate ~sp
    ~max_auth_age: 4 (* Requires that if the user logged in more that 4 seconds ago
                        he needs to relog in *)
    ~required: [Eliom_openid.Email] (* Requires his e-mail *)
    ~immediate: false
   url
   (fun sp result ->
     let string = 
       match result with
         | Setup_needed -> "setup needed" | Canceled -> "canceled"
         | Result result -> 
           try List.assoc Email result.fields with Not_found -> "No e-mail :(" 
     in 
     Eliom_sessions.set_volatile_session_data ~table:messages ~sp string;
     Eliom_predefmod.Redirection.send ~sp login_form))

open XHTML.M
let _ = Eliom_predefmod.Xhtml.register
    ~service: login_form
    (fun sp _ _ ->
    let message = 
       match Eliom_sessions.get_volatile_session_data ~table: messages ~sp () with
       | Eliom_sessions.Data s -> 
         Eliom_sessions.close_session ~sp ();
         [p [pcdata ("Authentification result: "^ s)]]
       | _ -> []
    in
    let form = 
    Eliom_predefmod.Xhtml.post_form ~service:form_handler ~sp
      (fun url ->
        [p [pcdata "Your OpenID identifier: ";
            Eliom_predefmod.Xhtml.string_input ~input_type:`Text ~name:url ();
            Eliom_predefmod.Xhtml.string_input ~input_type:`Submit ~value:"Login" ();
           ]]) ()
    in
    Lwt.return
      (html
           (head (title (pcdata "A sample test")) [])
           (body 
              (message @ [form]))))
]}
*)
    
(** {1 Documentation} *)

(** {2 Miscallenous} *)
(** Error that may happen when identifiying an user *)
type openid_error =
    Invalid_XRDS_File of string * string
        (** The provider XRDS file was not valid *)
  | Discovery_Error of string * string
      (** An error occured during the discovery of the provider *)
  | Missing_parameter of string
      (** The remote server forgot a parameter in its request *)
  | Invalid_signature of string * string
      (** We disagree with the server's signature *)
  | Invalid_association of string
      (** We were unable to associate with a provider *)
  | Invalid_argument of string * string * string
      (** The argument provided were not set to a correct value *)
  | Server_error of string
      (** The server threw an explicit error *)
  | Invalid_answer of string
      (** The answer code was not correct *)
  | Invalid_html_doc of string
      (** An error occured during the parsing of an user url in html format *)
(** Prettyprint an OpenID Error *)
val string_of_openid_error : openid_error -> string

(** Exception thrown by this module's function. *)
exception Error of openid_error

(** A field you can request to the provider *)
type field =
    Email
  | Fullname
  | DateOfBirth
  | PostCode
  | Timezone
  | Language
  | Country
  | Gender
  | Nickname

(** An extension yielding values of type 'a *)
type 'a extension = {
  headers : (string * string) list;
  parse : (string * string) list -> 'a Lwt.t;
}

(** The SREG extension
    @see <http://openid.net/specs/openid-simple-registration-extension-1_1-01.html> SREG *)
val sreg :
  ?policy_url:string ->
  required:field list ->
  optional:field list -> unit -> (field * string) list extension

(** The AX extension 
    @see <http://openid.net/specs/openid-attribute-exchange-1_0.html> AX*)
val ax :
  required:field list ->
  optional:field list -> unit -> (field * string) list extension

(** The pape data returned by the server *)
type pape = {
  auth_time : string option;
  (** The time at which the user last logged in *)
  policies : string list option;
  (** A list of policies (url) describing your usage of the data *)
  nist_level : int option;
  (** The nist level *)
}
val pape :
  ?max_auth_age:int -> ?auth_policies:string list -> unit -> pape extension
(** The PAPE extension.
    @see <http://openid.net/specs/openid-provider-authentication-policy-extension-1_0-01.html> PAPE *)

val ( *** ) : 'a extension -> 'b extension -> ('a * 'b) extension
(** Product of two extension *)

(** The result of an authentification. *)
type 'a authentification_result = 
    Canceled (** The user canceled the login (or failed) *)
  | Setup_needed (** The provider has not enough information to complete an immediate
                     request. Only returned when using an immediate authentification. *)
  | Result of 'a (** All went ok. *)


(** {2 Low-level interface.} *)

(** Perform discovery on an user-supplied url *)
val perform_discovery : string -> (string * string option) Lwt.t


(** Information about the hidden service *)
module type HiddenServiceInfo = sig
  val path : string list
(** The path of the hidden service *)
  val f :
    Eliom_sessions.server_params ->
    (string * string) list ->
    unit -> Eliom_predefmod.Any.page Lwt.t
(** The function called when an user connects to the hidden service
    (not that hidden) without being in an identification process.
    Typically you should redirect the user to the login page. *)
end
(** This functor build a hidden service that will be used
    to receive the remote server's data. In return
    you get a check function *)
module Make :
  functor
    (S : HiddenServiceInfo) ->
    sig
      val authentificate :
        mode:string ->
        ext:'a extension ->
        handler:(Eliom_sessions.server_params ->
                 'a authentification_result ->
                 Eliom_predefmod.Any.page Lwt.t) ->
        sp:Eliom_sessions.server_params ->
        discovery:string * string option -> XHTML.M.uri Lwt.t
        (** Authentificate an user.
            - mode: can be [checkid_setup] or [checkid_immediate]
                    whether you want immediate identification or not.
            - ext: the extensions you want to use.
            - handler: the handler called with the result of the authentification.
            - sp: the session parameters
            - discovery: The discovery information
           In return you get an URI you have to redirect the user to. *)
    end

(** {2 High-level interface} *)
(** The high-level interface takes care of creating
    the extension you want, without to use them directly.
    It yields a [result]. *)

(** The result yielded by the authentification process *)
type result = { 
  fields : (field * string) list; 
  (** The fields you requested *)
  pape : pape; 
  (** The pape information *)
}

(** The type of the authentificate function.
    - immediate: whether to use immediate identification or not (default: true)
    - sp: session params
    - policy_url: an optional policy url to describe what you do with the data (sreg) (default:none)
    - required: optional fields you really need (although the provier may not provide them) (default:empty)
    - optional: optional fields you don't really need (default: empty)
    - max_auth_age: Requires that the user logged in less than [n] seconds ago. (default: up to the provider)
    - auth_policies: A list of url describing your policies regarding the data (default: empty)
    - the url the user gave you
    - an handler, that'll be called after checking the parameters with the result
      and the server params of the GET request. You can send whatever page you want
      but you should redirect the user to a page so he can't bookmark it, or
      send some piece of html to interface with javascript.
*)
type check_fun =
    ?immediate:bool ->
    sp:Eliom_sessions.server_params ->
    ?policy_url:string ->
    ?max_auth_age:int ->
    ?auth_policies:string list ->
    ?required:field list ->
    ?optional:field list ->
    string ->
    (Eliom_sessions.server_params ->
     result authentification_result -> Eliom_predefmod.Any.page Lwt.t) ->
    XHTML.M.uri Lwt.t

(** Init the OpenID for your site.
    Takes a path and a handler for the hidden service *)
val init :
  path:string list ->
  f:(Eliom_sessions.server_params ->
     (string * string) list -> unit -> Eliom_predefmod.Any.page Lwt.t) ->
  check_fun
