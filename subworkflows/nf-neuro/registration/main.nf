include { REGISTRATION_ANATTODWI  } from '../../../modules/nf-neuro/registration/anattodwi/main'
include { REGISTRATION_ANTS   } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_EASYREG   } from '../../../modules/nf-neuro/registration/easyreg/main'
include { REGISTRATION_SYNTHMORPH } from '../../../modules/nf-neuro/registration/synthmorph/main'
include { REGISTRATION_CONVERT } from '../../../modules/nf-neuro/registration/convert/main'

params.run_easyreg      = false
params.run_synthmorph   = false


workflow REGISTRATION {

    // The subworkflow requires at least ch_fixed_image and ch_moving_image as inputs to
    // properly perform the registration. Supplying a ch_metric will select
    // the REGISTRATION_ANATTODWI module meanwhile NOT supplying a ch_metric
    // will select the REGISTRATION_ANTS (SyN or SyNQuick) module. Alternatively,
    // NOT supplying ch_metric and activating alternative module flag with select
    // REGISTRATION_EASYREG or REGISTRATION_SYNTHMORPH

    take:
        ch_fixed_image                  // channel: [ val(meta), image ]
        ch_moving_image                 // channel: [ val(meta), reference ]
        ch_metric                       // channel: [ val(meta), metric ], optional
        ch_fixed_mask                   // channel: [ val(meta), mask ], optional
        ch_segmentation                 // channel: [ val(meta), segmentation ], optional
        ch_moving_segmentation          // channel: [ val(meta), segmentation ], optional
        ch_freesurfer_license           // channel: [ license ], optional
    main:
        ch_versions = channel.empty()
        ch_mqc = channel.empty()

        if ( params.run_easyreg ) {
            // ** Registration using Easyreg ** //
            // Result : [ meta, reference, image | [], ref-segmentation | [], segmentation | [] ]
            //  Steps :
            //   - join [ meta, reference, image | null ]
            //   - join [ meta, reference, image | null, ref-segmentation | null ]
            //   - join [ meta, reference, image | null, ref-segmentation | null, segmentation | null ]
            //   -  map [ meta, reference, image | [], ref-segmentation | [], segmentation | [] ]
            ch_register = ch_moving_image
                .join(ch_fixed_image, remainder: true)
                .join(ch_moving_segmentation, remainder: true)
                .join(ch_segmentation, remainder: true)
                .map{ it[0..1] + [it[2] ?: [], it[3] ?: [], it[4] ?: []] }

            REGISTRATION_EASYREG ( ch_register )
            ch_versions = ch_versions.mix(REGISTRATION_EASYREG.out.versions.first())

            // ** Set compulsory outputs ** //
            out_image_warped = REGISTRATION_EASYREG.out.image_warped
            out_forward_affine = channel.empty()
            out_forward_warp = REGISTRATION_EASYREG.out.forward_warp
            out_backward_affine = channel.empty()
            out_backward_warp = REGISTRATION_EASYREG.out.backward_warp
            out_forward_image_transform = REGISTRATION_EASYREG.out.forward_warp
            out_backward_image_transform = REGISTRATION_EASYREG.out.backward_warp
            out_forward_tractogram_transform = REGISTRATION_EASYREG.out.backward_warp
            out_backward_tractogram_transform = REGISTRATION_EASYREG.out.forward_warp

            // ** Set optional outputs. ** //
            // If segmentations are not provided as inputs,
            // easyreg will outputs synthseg segmentations
            out_ref_warped = REGISTRATION_EASYREG.out.fixed_warped
            out_segmentation = ch_segmentation.mix( REGISTRATION_EASYREG.out.segmentation_warped )
            out_ref_segmentation = ch_moving_segmentation.mix( REGISTRATION_EASYREG.out.fixed_segmentation_warped )
        }
        else if ( params.run_synthmorph ) {
            // ** Registration using synthmorph ** //
            ch_register = ch_fixed_image
                .join(ch_moving_image)

            REGISTRATION_SYNTHMORPH ( ch_register )
            ch_versions = ch_versions.mix(REGISTRATION_SYNTHMORPH.out.versions.first())

            // Tag all synthmorph transforms per type, and index if in a chain. This info will be
            // used after conversion to sort out the transforms from the conversion module.
            ch_convert_forward_affine = REGISTRATION_SYNTHMORPH.out.forward_affine
                .map{ meta, forward_affine -> [meta, [tag: "forward_affine"], forward_affine] }
            ch_convert_forward_warp = REGISTRATION_SYNTHMORPH.out.forward_warp
                .map{ meta, forward_warp -> [meta, [tag: "forward_warp"], forward_warp] }
            ch_convert_backward_affine = REGISTRATION_SYNTHMORPH.out.backward_affine
                .map{ meta, backward_affine -> [meta, [tag: "backward_affine"], backward_affine] }
            ch_convert_backward_warp = REGISTRATION_SYNTHMORPH.out.backward_warp
                .map{ meta, backward_warp -> [meta, [tag: "backward_warp"], backward_warp] }
            ch_convert_forward_image_transform = REGISTRATION_SYNTHMORPH.out.forward_image_transform
                .map{ meta, transforms -> [meta, [tag: "forward_image_transform"], 0..<transforms.size(), transforms] }
                .transpose()
                .map{ meta, tag, idx, transform -> [meta, tag + [idx: idx], transform]}
            ch_convert_backward_image_transform = REGISTRATION_SYNTHMORPH.out.backward_image_transform
                .map{ meta, transforms -> [meta, [tag: "backward_image_transform"], 0..<transforms.size(), transforms] }
                .transpose()
                .map{ meta, tag, idx, transform -> [meta, tag + [idx: idx], transform]}

            // Mix all transforms into a single channel for conversion
            ch_convert = ch_convert_forward_affine
                .mix(ch_convert_forward_warp)
                .mix(ch_convert_backward_affine)
                .mix(ch_convert_backward_warp)
                .mix(ch_convert_forward_image_transform)
                .mix(ch_convert_backward_image_transform)
                .combine(ch_fixed_image, by: 0)
                .combine(ch_moving_image, by: 0)
                .map{ meta, tag, transform, fixed, moving ->
                    def extension = transform.name.tokenize('.')[1..-1].join(".")
                    return [
                        meta + tag + [cache: meta],
                        transform,
                        extension == "lta" ? "lta" : "ras",
                        "itk",
                        extension == "lta" ? fixed : moving,
                        [],
                    ]}
                .combine(ch_freesurfer_license)

            REGISTRATION_CONVERT ( ch_convert )
            ch_versions = ch_versions.mix(REGISTRATION_CONVERT.out.versions.first())

            // Un-mix conversion outputs using the tags. Save indexes for output sorting
            ch_conversion_outputs = REGISTRATION_CONVERT.out.transformation
                .branch{ meta, transform ->
                    forward_affine: meta.tag == "forward_affine"
                        return [meta.cache, transform]
                    forward_warp: meta.tag == "forward_warp"
                        return [meta.cache, transform]
                    backward_affine: meta.tag == "backward_affine"
                        return [meta.cache, transform]
                    backward_warp: meta.tag == "backward_warp"
                        return [meta.cache, transform]
                    forward_image_transform: meta.tag == "forward_image_transform"
                        return [meta.cache, [idx: meta.idx, trans: transform]]
                    backward_image_transform: meta.tag == "backward_image_transform"
                        return [meta.cache, [idx: meta.idx, trans: transform]]
                }

            // ** Set compulsory outputs ** //
            out_image_warped = REGISTRATION_SYNTHMORPH.out.image_warped
            out_forward_affine = ch_conversion_outputs.forward_affine
            out_forward_warp = ch_conversion_outputs.forward_warp
            out_backward_affine = ch_conversion_outputs.backward_affine
            out_backward_warp = ch_conversion_outputs.backward_warp
            out_forward_image_transform = ch_conversion_outputs.forward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_backward_image_transform = ch_conversion_outputs.backward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_forward_tractogram_transform = out_backward_image_transform
            out_backward_tractogram_transform = out_forward_image_transform
            // ** and optional outputs. ** //
            out_ref_warped = channel.empty()
            out_segmentation = channel.empty()
            out_ref_segmentation = channel.empty()
        }
        else {
            // ** Classic registration using antsRegistration  ** //
            // Result : [ meta, image, reference, metric | [] ]
            //  Steps :
            //   - join [ meta, image, ref ]
            //   - join [ meta, image, ref, metric | null ]
            //   - map  [ meta, image, ref, metric | [] ]
            // Branches :
            //   - anat_to_dwi : has a metric at index 3
            //   - ants_syn    : doesn't have a metric at index 3 ( [] or null )
            ch_register = ch_fixed_image
                .join(ch_moving_image)
                .join(ch_metric, remainder: true)
                .map{ it[0..2] + [it[3] ?: []] }
                .branch{
                    anat_to_dwi : it[3]
                    ants_syn: true
                }

            // ** Registration using ANAT TO DWI ** //
            REGISTRATION_ANATTODWI ( ch_register.anat_to_dwi )
            ch_versions = ch_versions.mix(REGISTRATION_ANATTODWI.out.versions.first())
            ch_mqc = ch_mqc.mix(REGISTRATION_ANATTODWI.out.mqc)

            // ** Set compulsory outputs ** //
            out_image_warped = REGISTRATION_ANATTODWI.out.anat_warped
            out_forward_affine = REGISTRATION_ANATTODWI.out.forward_affine
            out_forward_warp = REGISTRATION_ANATTODWI.out.forward_warp
            out_backward_affine = REGISTRATION_ANATTODWI.out.backward_affine
            out_backward_warp = REGISTRATION_ANATTODWI.out.backward_warp
            out_forward_image_transform = REGISTRATION_ANATTODWI.out.forward_image_transform
            out_backward_image_transform = REGISTRATION_ANATTODWI.out.backward_image_transform
            out_forward_tractogram_transform = REGISTRATION_ANATTODWI.out.forward_tractogram_transform
            out_backward_tractogram_transform = REGISTRATION_ANATTODWI.out.backward_tractogram_transform

            // ** Registration using ANTS SYN SCRIPTS ** //
            // Registration using antsRegistrationSyN.sh or antsRegistrationSyNQuick.sh, has
            // to be defined in the config file or else the default (SyN) will be used.
            // Result : [ meta, image, mask | [] ]
            //  Steps :
            //   - join [ meta, image, metric | [], mask | null ]
            //   - map  [ meta, image, mask | [] ]
            ch_register = ch_register.ants_syn
                .join(ch_fixed_mask, remainder: true)
                .map{ it[0..2] + [it[4] ?: []] }

            REGISTRATION_ANTS ( ch_register )
            ch_versions = ch_versions.mix(REGISTRATION_ANTS.out.versions.first())
            ch_mqc = ch_mqc.mix(REGISTRATION_ANTS.out.mqc)

            // ** Set compulsory outputs ** //
            out_image_warped = out_image_warped.mix(REGISTRATION_ANTS.out.image_warped)
            out_forward_affine = out_forward_affine.mix(REGISTRATION_ANTS.out.forward_affine)
            out_forward_warp = out_forward_warp.mix(REGISTRATION_ANTS.out.forward_warp)
            out_backward_affine = out_backward_affine.mix(REGISTRATION_ANTS.out.backward_affine)
            out_backward_warp = out_backward_warp.mix(REGISTRATION_ANTS.out.backward_warp)
            out_forward_image_transform = out_forward_image_transform.mix(REGISTRATION_ANTS.out.forward_image_transform)
            out_backward_image_transform = out_backward_image_transform.mix(REGISTRATION_ANTS.out.backward_image_transform)
            out_forward_tractogram_transform = out_forward_tractogram_transform.mix(REGISTRATION_ANTS.out.forward_tractogram_transform)
            out_backward_tractogram_transform = out_backward_tractogram_transform.mix(REGISTRATION_ANTS.out.backward_tractogram_transform)

            // **and optional outputs **//
            out_ref_warped = channel.empty()
            out_segmentation = channel.empty()
            out_ref_segmentation = channel.empty()
        }
    emit:
        image_warped                    = out_image_warped                  // channel: [ val(meta), image ]
        reference_warped                = out_ref_warped                    // channel: [ val(meta), ref ]
        // Individual transforms
        forward_affine                  = out_forward_affine                // channel: [ val(meta), <forward-affine> ]
        forward_warp                    = out_forward_warp                  // channel: [ val(meta), <forward-warp> ]
        backward_warp                   = out_backward_warp                 // channel: [ val(meta), <backward-warp> ]
        backward_affine                 = out_backward_affine               // channel: [ val(meta), <backward-affine> ]
        // Combined transforms
        forward_image_transform         = out_forward_image_transform       // channel: [ val(meta), [ <forward-warp>, <forward-affine> ] ]
        backward_image_transform        = out_backward_image_transform      // channel: [ val(meta), [ <backward-affine>, <backward-warp> ] ]
        forward_tractogram_transform    = out_forward_tractogram_transform  // channel: [ val(meta), [ <forward-warp>, <forward-affine> ] ]
        backward_tractogram_transform   = out_backward_tractogram_transform // channel: [ val(meta), [ <forward-warp>, <forward-affine> ] ]
        // Segmentations
        segmentation                    = out_segmentation                  // channel: [ val(meta), segmentation ]
        reference_segmentation          = out_ref_segmentation              // channel: [ val(meta), ref-segmentation ]

        mqc                             = ch_mqc                            // channel: [ *mqc.*, ... ]
        versions                        = ch_versions                       // channel: [ versions.yml ]
}
