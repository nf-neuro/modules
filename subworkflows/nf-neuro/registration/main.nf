include { REGISTRATION_ANATTODWI  } from '../../../modules/nf-neuro/registration/anattodwi/main'
include { REGISTRATION_ANTS   } from '../../../modules/nf-neuro/registration/ants/main'
include { REGISTRATION_EASYREG   } from '../../../modules/nf-neuro/registration/easyreg/main'
include { REGISTRATION_SYNTHMORPH } from '../../../modules/nf-neuro/registration/synthmorph/main'
include { REGISTRATION_CONVERT as CONVERT_SYNTHMORPH } from '../../../modules/nf-neuro/registration/convert/main'
include { REGISTRATION_CONVERT as CONVERT_EASYREG } from '../../../modules/nf-neuro/registration/convert/main'
include { REGISTRATION_DEFORM2DISP as DEFORM2DISP_FORWARD } from '../../../modules/nf-neuro/registration/deform2disp/main'
include { REGISTRATION_DEFORM2DISP as DEFORM2DISP_BACKWARD } from '../../../modules/nf-neuro/registration/deform2disp/main'
include { UTILS_OPTIONS } from '../utils_options/main'
include { IMAGE_APPLYMASK as MASK_FIXED_IMAGE} from '../../../modules/nf-neuro/image/applymask/main'
include { IMAGE_APPLYMASK as MASK_FIXED_METRIC} from '../../../modules/nf-neuro/image/applymask/main'
include { IMAGE_APPLYMASK as MASK_MOVING_IMAGE} from '../../../modules/nf-neuro/image/applymask/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as WARP_IMAGE_TO_FIXED } from '../../../modules/nf-neuro/registration/antsapplytransforms/main'
include { REGISTRATION_ANTSAPPLYTRANSFORMS as WARP_IMAGE_TO_MOVING } from '../../../modules/nf-neuro/registration/antsapplytransforms/main'

workflow REGISTRATION {

    // The subworkflow requires at least ch_fixed_image and ch_moving_image as inputs to
    // properly perform the registration. Supplying a ch_metric will select
    // the REGISTRATION_ANATTODWI module meanwhile NOT supplying a ch_metric
    // will select the REGISTRATION_ANTS (SyN or SyNQuick) module. Alternatively,
    // NOT supplying ch_metric and activating alternative module flag with select
    // REGISTRATION_EASYREG or REGISTRATION_SYNTHMORPH

    take:
        ch_fixed_image                  // channel: [ val(meta), fixed_image ]
        ch_moving_image                 // channel: [ val(meta), moving_image ]
        ch_metric                       // channel: [ val(meta), metric ], optional
        ch_fixed_mask                   // channel: [ val(meta), fixed_mask ], optional
        ch_moving_mask                  // channel: [ val(meta), moving_mask ], optional
        ch_segmentation                 // channel: [ val(meta), segmentation ], optional
        ch_moving_segmentation          // channel: [ val(meta), segmentation ], optional
        ch_freesurfer_license           // channel: [ license ], optional
        options                         // Map of options

    main:
        ch_versions = channel.empty()
        ch_mqc = channel.empty()

        // Merge options with defaults from meta.yml
        UTILS_OPTIONS("${moduleDir}/meta.yml", options, true)
        options = UTILS_OPTIONS.out.options.value

        if ( ( options.masking_strategy == "both" || options.masking_strategy == "internal" ) && ( options.method == "easyreg" || options.method == "synthmorph" ) ) {
            error "The ${options.masking_strategy} masking strategy is not compatible with the easyreg or synthmorph registration methods."
        }

        // Initialize channels
        ch_fixed_image_ready  = ch_fixed_image
        ch_moving_image_ready = ch_moving_image
        ch_fixed_metric_ready = ch_metric
        if ( options.masking_strategy == "apriori" || options.masking_strategy == "both" ) {
            MASK_FIXED_IMAGE ( ch_fixed_image.join(ch_fixed_mask) )
            ch_fixed_image_ready = ch_fixed_image.join(MASK_FIXED_IMAGE.out.image, remainder: true)
                                    .map({ meta, orig, masked -> [meta, masked?: orig] })
            ch_versions = ch_versions.mix(MASK_FIXED_IMAGE.out.versions.first())

            MASK_FIXED_METRIC ( ch_metric.join(ch_fixed_mask) )
            ch_fixed_metric_ready = ch_metric.join(MASK_FIXED_METRIC.out.image, remainder: true)
                                        .map({ meta, orig, masked -> [meta, masked?: orig] })
            ch_versions = ch_versions.mix(MASK_FIXED_METRIC.out.versions.first())

            MASK_MOVING_IMAGE ( ch_moving_image.join(ch_moving_mask) )
            ch_moving_image_ready = ch_moving_image.join(MASK_MOVING_IMAGE.out.image, remainder: true)
                                    .map({ meta, orig, masked -> [meta, masked?: orig] })
            ch_versions = ch_versions.mix(MASK_MOVING_IMAGE.out.versions.first())
        }

        if ( options.method !in ["ants", "easyreg", "synthmorph"] ) {
            error "Unsupported registration method '${options.method}'."
        }

        if ( options.masking_strategy !in ["none", "apriori", "internal", "both"] ) {
            error "Unsupported masking strategy '${options.masking_strategy}'."
        }

        if ( options.method == "easyreg" ) {
            // ** Registration using Easyreg ** //
            // Result : [ meta, fixed, moving, fixed_segmentation | [], moving_segmentation | [] ]
            //  Steps :
            //   - join [ meta, fixed, moving ]
            //   - join [ meta, fixed, moving, fixed_segmentation | null ]
            //   - join [ meta, fixed, moving, fixed_segmentation | null, moving_segmentation | null ]
            //   -  map [ meta, fixed, moving, fixed_segmentation | [], moving_segmentation | [] ]
            ch_register = ch_fixed_image_ready
                .join(ch_moving_image_ready)
                .join(ch_segmentation, remainder: true)
                .join(ch_moving_segmentation, remainder: true)
                .map{ it[0..1] + [it[2] ?: [], it[3] ?: [], it[4] ?: []] }

            REGISTRATION_EASYREG ( ch_register )
            ch_versions = ch_versions.mix(REGISTRATION_EASYREG.out.versions.first())

            DEFORM2DISP_FORWARD ( REGISTRATION_EASYREG.out.forward_warp )
            ch_versions = ch_versions.mix(DEFORM2DISP_FORWARD.out.versions.first())

            DEFORM2DISP_BACKWARD ( REGISTRATION_EASYREG.out.backward_warp )

            ch_convert_easyreg_forward_warp = DEFORM2DISP_FORWARD.out.transformation
                .map{ meta, transform -> [meta, [tag: "forward_warp"], transform] }
            ch_convert_easyreg_backward_warp = DEFORM2DISP_BACKWARD.out.transformation
                .map{ meta, transform -> [meta, [tag: "backward_warp"], transform] }

            ch_convert_easyreg = ch_convert_easyreg_forward_warp
                .mix(ch_convert_easyreg_backward_warp)
                .combine(ch_fixed_image, by: 0)
                .combine(ch_moving_image, by: 0)
                .map{ meta, tag, transform, fixed, moving ->
                    def extension = transform.name.tokenize('.')[1..-1].join(".")
                    return [
                        meta + tag + [cache: meta],
                        transform,
                        "ras",
                        "itk",
                        extension == "lta" ? fixed : moving,
                        [],
                    ]}
                .combine(ch_freesurfer_license)

            CONVERT_EASYREG ( ch_convert_easyreg )
            ch_versions = ch_versions.mix(CONVERT_EASYREG.out.versions.first())

            // Un-mix conversion outputs using the tags. Save indexes for output sorting
            ch_conversion_easyreg_outputs = CONVERT_EASYREG.out.transformation
                .branch{ meta, transform ->
                    forward_warp: meta.tag == "forward_warp"
                        return [meta.cache, transform]
                    backward_warp: meta.tag == "backward_warp"
                        return [meta.cache, transform]
                    forward_image_transform: meta.tag == "forward_image_transform"
                        return [meta.cache, [idx: meta.idx, trans: transform]]
                    backward_image_transform: meta.tag == "backward_image_transform"
                        return [meta.cache, [idx: meta.idx, trans: transform]]
                }

            // ** Set compulsory outputs ** //
            out_image_warped = REGISTRATION_EASYREG.out.image_warped
            out_fixed_warped = REGISTRATION_EASYREG.out.fixed_warped
            out_forward_affine = channel.empty()
            out_forward_warp = ch_conversion_easyreg_outputs.forward_warp
            out_backward_affine = channel.empty()
            out_backward_warp = ch_conversion_easyreg_outputs.backward_warp
            out_forward_image_transform = ch_conversion_easyreg_outputs.forward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_backward_image_transform = ch_conversion_easyreg_outputs.backward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_forward_tractogram_transform = ch_conversion_easyreg_outputs.backward_warp
            out_backward_tractogram_transform = ch_conversion_easyreg_outputs.forward_warp

            // ** Set optional outputs. ** //
            // If segmentations are not provided as inputs,
            // easyreg will outputs synthseg segmentations
            out_segmentation = ch_segmentation.mix( REGISTRATION_EASYREG.out.segmentation_warped )
            out_fixed_segmentation = ch_moving_segmentation.mix( REGISTRATION_EASYREG.out.fixed_segmentation_warped )
        }
        else if ( options.method == "synthmorph" ) {
            // ** Registration using synthmorph ** //
            ch_register = ch_fixed_image_ready
                .join(ch_moving_image_ready)

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
            ch_convert_synthmorph = ch_convert_forward_affine
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

            CONVERT_SYNTHMORPH ( ch_convert_synthmorph )
            ch_versions = ch_versions.mix(CONVERT_SYNTHMORPH.out.versions.first())

            // Un-mix conversion outputs using the tags. Save indexes for output sorting
            ch_conversion_synthmorph_outputs = CONVERT_SYNTHMORPH.out.transformation
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
            out_fixed_warped = REGISTRATION_SYNTHMORPH.out.fixed_warped
            out_forward_affine = ch_conversion_synthmorph_outputs.forward_affine
            out_forward_warp = ch_conversion_synthmorph_outputs.forward_warp
            out_backward_affine = ch_conversion_synthmorph_outputs.backward_affine
            out_backward_warp = ch_conversion_synthmorph_outputs.backward_warp
            out_forward_image_transform = ch_conversion_synthmorph_outputs.forward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_backward_image_transform = ch_conversion_synthmorph_outputs.backward_image_transform
                .groupTuple()
                .map{ meta, trans -> [meta, trans.sort{ t1, t2 -> t1.idx <=> t2.idx }.collect{ it.trans }] }
            out_forward_tractogram_transform = out_backward_image_transform
            out_backward_tractogram_transform = out_forward_image_transform
            // ** and optional outputs. ** //
            out_segmentation = channel.empty()
            out_fixed_segmentation = channel.empty()
        }
        else {
            // ** Classic registration using antsRegistration  ** //
            // Result : [ meta, fixed, moving, metric | [] ]
            //  Steps :
            //   - join [ meta, fixed, moving ]
            //   - join [ meta, fixed, moving, metric | null ]
            //   - map  [ meta, fixed, moving, metric | [] ]
            // Branches :
            //   - anat_to_dwi : has a metric at index 3
            //   - ants_syn    : doesn't have a metric at index 3 ( [] or null )
            ch_register = ch_fixed_image_ready
                .join(ch_moving_image_ready)
                .join(ch_fixed_metric_ready, remainder: true)
            if ( options.masking_strategy == "both" || options.masking_strategy == "internal" ) {
                ch_register = ch_register
                    .join(ch_fixed_mask, remainder: true)
                    .join(ch_moving_mask, remainder: true)
                    .map{ it[0..2] + [it[3] ?: [], it[4] ?: [], it[5] ?: []] }
            }
            else {
                ch_register = ch_register
                    .map{ it[0..2] + [it[3] ?: [], [], []] }
            }

            ch_register = ch_register.branch{
                anat_to_dwi : it[3]
                ants_syn: true
                    return it[0..2] + it[4..5]
            }

            // ** Registration using ANAT TO DWI ** //
            REGISTRATION_ANATTODWI ( ch_register.anat_to_dwi )
            ch_versions = ch_versions.mix(REGISTRATION_ANATTODWI.out.versions.first())
            ch_mqc = ch_mqc.mix(REGISTRATION_ANATTODWI.out.mqc)

            // ** Set compulsory outputs ** //
            out_image_warped = REGISTRATION_ANATTODWI.out.image_warped
            out_fixed_warped = REGISTRATION_ANATTODWI.out.fixed_warped
            out_forward_affine = REGISTRATION_ANATTODWI.out.forward_affine
            out_forward_warp = REGISTRATION_ANATTODWI.out.forward_warp
            out_backward_affine = REGISTRATION_ANATTODWI.out.backward_affine
            out_backward_warp = REGISTRATION_ANATTODWI.out.backward_warp
            out_forward_image_transform = REGISTRATION_ANATTODWI.out.forward_image_transform
            out_backward_image_transform = REGISTRATION_ANATTODWI.out.backward_image_transform
            out_forward_tractogram_transform = REGISTRATION_ANATTODWI.out.forward_tractogram_transform
            out_backward_tractogram_transform = REGISTRATION_ANATTODWI.out.backward_tractogram_transform

            REGISTRATION_ANTS ( ch_register.ants_syn )
            ch_versions = ch_versions.mix(REGISTRATION_ANTS.out.versions.first())
            ch_mqc = ch_mqc.mix(REGISTRATION_ANTS.out.mqc)

            // ** Set compulsory outputs ** //
            out_image_warped = out_image_warped.mix(REGISTRATION_ANTS.out.image_warped)
            out_fixed_warped = out_fixed_warped.mix(REGISTRATION_ANTS.out.fixed_warped)
            out_forward_affine = out_forward_affine.mix(REGISTRATION_ANTS.out.forward_affine)
            out_forward_warp = out_forward_warp.mix(REGISTRATION_ANTS.out.forward_warp)
            out_backward_affine = out_backward_affine.mix(REGISTRATION_ANTS.out.backward_affine)
            out_backward_warp = out_backward_warp.mix(REGISTRATION_ANTS.out.backward_warp)
            out_forward_image_transform = out_forward_image_transform.mix(REGISTRATION_ANTS.out.forward_image_transform)
            out_backward_image_transform = out_backward_image_transform.mix(REGISTRATION_ANTS.out.backward_image_transform)
            out_forward_tractogram_transform = out_forward_tractogram_transform.mix(REGISTRATION_ANTS.out.forward_tractogram_transform)
            out_backward_tractogram_transform = out_backward_tractogram_transform.mix(REGISTRATION_ANTS.out.backward_tractogram_transform)

            // **and optional outputs **//
            out_segmentation = channel.empty()
            out_fixed_segmentation = channel.empty()
        }

        out_image_warped_masked = out_image_warped
            .join(ch_moving_mask)
            .filter{ _meta, _warped, mask -> options.masking_strategy in ["both", "apriori"] && mask }
            .map{ meta, warped, _mask -> [meta, warped] }

        out_fixed_warped_masked = out_fixed_warped
            .join(ch_fixed_mask)
            .filter{ _meta, _warped, mask -> options.masking_strategy in ["both", "apriori"] && mask }
            .map{ meta, warped, _mask -> [meta, warped] }

        // Register original moving image
        ch_moving_transform = ch_moving_image
            .join(ch_fixed_image)
            .join(out_forward_image_transform)
            .join(ch_moving_mask)
            .filter{ _meta, _moving, _fixed, _transform, mask -> options.masking_strategy in ["apriori", "both"] && mask }
            .map{ meta, moving, fixed, transform, _mask -> [meta, moving, fixed, transform] }

        WARP_IMAGE_TO_FIXED ( ch_moving_transform )

        out_image_warped = out_image_warped
            .join(WARP_IMAGE_TO_FIXED.out.warped_image, remainder: true)
            .map{ meta, warped, warped_from_mask -> [meta, (warped_from_mask ?: warped)] }
        ch_versions = ch_versions.mix(WARP_IMAGE_TO_FIXED.out.versions.first())

        // Register original fixed image
        ch_fixed_transform = ch_fixed_image
            .join(ch_moving_image)
            .join(out_backward_image_transform)
            .join(ch_fixed_mask)
            .filter{ _meta, _fixed, _moving, _transform, mask -> options.masking_strategy in ["apriori", "both"] && mask }
            .map{ meta, fixed, moving, transform, _mask -> [meta, fixed, moving, transform] }

        WARP_IMAGE_TO_MOVING ( ch_fixed_transform )

        out_fixed_warped = out_fixed_warped
            .join(WARP_IMAGE_TO_MOVING.out.warped_image, remainder: true)
            .map{ meta, warped, warped_from_mask -> [meta, (warped_from_mask ?: warped)] }
        ch_versions = ch_versions.mix(WARP_IMAGE_TO_MOVING.out.versions.first())

    emit:
        image_warped                    = out_image_warped                  // channel: [ val(meta), image ]
        fixed_warped                    = out_fixed_warped                    // channel: [ val(meta), fixed ]
        image_warped_masked             = out_image_warped_masked           // channel: [ val(meta), image ]
        fixed_warped_masked             = out_fixed_warped_masked             // channel: [ val(meta), fixed ]
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
        fixed_segmentation              = out_fixed_segmentation              // channel: [ val(meta), fixed-segmentation ]

        mqc                             = ch_mqc                            // channel: [ *mqc.*, ... ]
        versions                        = ch_versions                       // channel: [ versions.yml ]
}
