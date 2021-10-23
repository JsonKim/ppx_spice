open Ppxlib
open Parsetree
open Ast_helper
open Utils

let addParams paramNames expr =
  List.fold_right
    (fun s acc ->
      let pat = Pat.var (mknoloc s) in
      Exp.fun_ Asttypes.Nolabel None pat acc)
    paramNames
    [%expr fun v -> [%e expr] v]

let generateCodecDecls typeName paramNames (encoder, decoder) =
  let encoderPat = Pat.var (mknoloc (typeName ^ Utils.encoderFuncSuffix)) in
  let encoderParamNames = List.map (fun s -> encoderVarPrefix ^ s) paramNames in

  let decoderPat = Pat.var (mknoloc (typeName ^ Utils.decoderFuncSuffix)) in
  let decoderParamNames = List.map (fun s -> decoderVarPrefix ^ s) paramNames in

  let vbs = [] in

  let vbs =
    match encoder with
    | None -> vbs
    | Some encoder ->
        vbs
        @ [
            Vb.mk
              ~attrs:[ attrWarning [%expr "-39"] ]
              encoderPat
              (addParams encoderParamNames encoder);
          ]
  in

  let vbs =
    match decoder with
    | None -> vbs
    | Some decoder ->
        vbs
        @ [
            Vb.mk
              ~attrs:[ attrWarning [%expr "-4"]; attrWarning [%expr "-39"] ]
              decoderPat
              (addParams decoderParamNames decoder);
          ]
  in

  vbs

let mapTypeDecl decl =
  let {
    ptype_attributes;
    ptype_name = { txt = typeName };
    ptype_manifest;
    ptype_params;
    ptype_loc;
    ptype_kind;
  } =
    decl
  in

  let isUnboxed =
    match Utils.getAttributeByName ptype_attributes "unboxed" with
    | Ok (Some _) -> true
    | _ -> false
  in

  match getGeneratorSettingsFromAttributes ptype_attributes with
  | Ok None -> []
  | Ok (Some generatorSettings) -> (
      match (ptype_manifest, ptype_kind) with
      | None, Ptype_abstract ->
          fail ptype_loc "Can't generate codecs for unspecified type"
      | Some { ptyp_desc = Ptyp_variant (rowFields, _, _) }, Ptype_abstract ->
          generateCodecDecls typeName
            (getParamNames ptype_params)
            (Polyvariants.generateCodecs generatorSettings rowFields isUnboxed)
      | None, Ptype_variant decls ->
          generateCodecDecls typeName
            (getParamNames ptype_params)
            (Variants.generateCodecs generatorSettings decls isUnboxed)
      | _ -> fail ptype_loc "This type is not handled by spice")
  | Error s -> fail ptype_loc s

let mapStructureItem mapper ({ pstr_desc } as structureItem) =
  match pstr_desc with
  | Pstr_type (recFlag, decls) -> (
      let valueBindings = decls |> List.map mapTypeDecl |> List.concat in
      [ mapper#structure_item structureItem ]
      @
      match List.length valueBindings > 0 with
      | true -> [ Str.value recFlag valueBindings ]
      | false -> [])
  | _ -> [ mapper#structure_item structureItem ]
