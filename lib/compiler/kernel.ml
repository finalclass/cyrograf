(* Shared types of the compiler boundary. *)

type source = {
  name : string;
  text : string;
}

type target =
  | Ocaml
  | Typescript
  | Go
  | Dart
  | Python
  | Java
  | Csharp
  | Rust

type format = Wire_v1

type ocaml_profile =
  | Native
  | Js

type artifact = {
  path : string;
  contents : string;
}